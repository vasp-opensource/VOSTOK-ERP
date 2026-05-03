-- ch_purch_to_wh: поступление по закупке на склад (change → Main, обновление связанных move).
-- Блокировка: lock_ch_purch_to_wh
--
-- Требования к БД: колонки Main.Source, Transactions.Source (sql/alter_Main_Source.sql, alter_transactions_Source.sql).
-- Значение «Разные» в Source не используется: в Main копируются только «Покупное» / «Собственное производство»;
-- при расхождении с Main строка Transactions не перезаписывается на «Разные».
-- Приёмка на склад выполняется только по строкам с заполненными Document_no и Document_date.
--
-- Source:
--   1) INSERT Main — если карточки по ERP_ID ещё нет;
--   2) UPDATE Main.Source — только если Main.Source пусто (NULL), из первой по id строки батча (допустимые значения — как в ENUM Main).
--
-- #1137: во временной таблице нельзя дважды открыть её в одном операторе — используется tmp_purch_erp_minid (MIN(id) по ERP_ID).

DELIMITER $$

DROP PROCEDURE IF EXISTS ch_purch_to_wh$$

CREATE PROCEDURE ch_purch_to_wh()
BEGIN
    DECLARE v_lock_ok INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        IF v_lock_ok = 1 THEN
            DO RELEASE_LOCK('lock_ch_purch_to_wh');
        END IF;
        RESIGNAL;
    END;

    SELECT GET_LOCK('lock_ch_purch_to_wh', 30) INTO v_lock_ok;


    IF COALESCE(v_lock_ok, 0) <> 1 THEN

        SET @erp_batch_blocked_message = 'Blocked: lock_ch_purch_to_wh lock is already held';

    END IF;


    IF COALESCE(v_lock_ok, 0) <> 1 THEN

        SET @erp_batch_blocked_message = 'Blocked: lock_ch_purch_to_wh lock is already held';

    END IF;

    IF v_lock_ok = 1 THEN
        START TRANSACTION;

        DROP TEMPORARY TABLE IF EXISTS tmp_purch_to_wh_ids;
        CREATE TEMPORARY TABLE tmp_purch_to_wh_ids (
            id INT UNSIGNED PRIMARY KEY,
            ERP_ID VARCHAR(255) NOT NULL,
            Advanced_group TEXT NULL,
            Quantity_change BIGINT NOT NULL
        );

        INSERT INTO tmp_purch_to_wh_ids (id, ERP_ID, Advanced_group, Quantity_change)
        SELECT
            t.id,
            t.ERP_ID,
            t.Advanced_group,
            COALESCE(t.Quantity_change, 0)
        FROM `Transactions` t
        WHERE t.type = 'change'
          AND t.Status_transaction = 'В ожидании'
          AND t.Status_warehouse = 'В закупке'
          AND t.where_from = 'внешний'
          AND t.where_to = 'склад'
          AND t.Order_wh = 'Принято на склад'
          AND t.Order_purch = 'Оплачено'
          AND t.Document_no IS NOT NULL
          AND TRIM(COALESCE(t.Document_no, '')) <> ''
          AND t.Document_date IS NOT NULL
          AND t.Cost_total_rub IS NOT NULL
          AND t.Cost_total_rub > 0
          AND COALESCE(t.Quantity_change, 0) > 0;

        DROP TEMPORARY TABLE IF EXISTS tmp_purch_erp_minid;
        CREATE TEMPORARY TABLE tmp_purch_erp_minid (
            ERP_ID VARCHAR(255) NOT NULL,
            mid INT UNSIGNED NOT NULL,
            PRIMARY KEY (ERP_ID)
        );
        INSERT INTO tmp_purch_erp_minid (ERP_ID, mid)
        SELECT ERP_ID, MIN(id)
        FROM tmp_purch_to_wh_ids
        GROUP BY ERP_ID;

        /* ========== Блок INSERT: новая строка Main по ERP_ID из батча (первая по MIN(id)) ========== */
        INSERT INTO `Main` (
            created_at,
            updated_at,
            created_by,
            updated_by,
            ERP_ID,
            Supplied_component_number,
            Component_revision,
            Component_name,
            Components_quantity_in_assembly,
            inProcess_purchase,
            Component_type,
            Part_material, Producer, Catalogue_number, Producer_article, Distributer,
            Distributer_article, MBOM_type, Mass_kg, Unit_of_measure, Height, Width, Length
        )
        SELECT
            NOW(),
            NOW(),
            'ch_purch_to_wh',
            'ch_purch_to_wh',
            t.ERP_ID,
            MIN(t.Supplied_component_number),
            MIN(t.Component_revision),
            MIN(t.Component_name),
            MIN(COALESCE(t.Components_quantity_in_assembly, 0)),
            0,
            MIN(t.Component_type),
            MIN(t.Part_material), MIN(t.Producer), MIN(t.Catalogue_number), MIN(t.Producer_article),
            MIN(t.Distributer), MIN(t.Distributer_article), MIN(t.MBOM_type), MIN(t.Mass_kg),
            MIN(t.Unit_of_measure), MIN(t.Height), MIN(t.Width), MIN(t.Length)
        FROM tmp_purch_to_wh_ids x
        INNER JOIN tmp_purch_erp_minid pick ON pick.ERP_ID = x.ERP_ID AND pick.mid = x.id
        INNER JOIN `Transactions` t ON t.id = x.id
        WHERE NOT EXISTS (
            SELECT 1
            FROM `Main` m
            WHERE m.ERP_ID = t.ERP_ID
        )
        GROUP BY t.ERP_ID;

        /* ========== Блок Main.Source: пустое поле — перенос из Transactions.Source (первая строка батча по ERP_ID) ========== */
        UPDATE `Main` m
        INNER JOIN (
            SELECT
                x.ERP_ID,
                tx.`Source` AS src
            FROM tmp_purch_to_wh_ids x
            INNER JOIN `Transactions` tx ON tx.id = x.id
            INNER JOIN tmp_purch_erp_minid pick ON pick.ERP_ID = x.ERP_ID AND pick.mid = x.id
        ) fs ON fs.ERP_ID = m.ERP_ID
        SET
            m.`Source`     = fs.src,
            m.`updated_at` = NOW(),
            m.`updated_by` = 'ch_purch_to_wh'
        WHERE fs.src IS NOT NULL
          AND m.`Source` IS NULL
          AND fs.src IN ('Покупное', 'Собственное производство');

        /* move: «Ожидание закупки» → «Дефицит склада» */
        UPDATE `Transactions` mv
        JOIN (
            SELECT DISTINCT ERP_ID, Advanced_group
            FROM tmp_purch_to_wh_ids
        ) g
          ON g.ERP_ID = mv.ERP_ID
         AND (
              (g.Advanced_group = mv.Advanced_group)
              OR (g.Advanced_group IS NULL AND mv.Advanced_group IS NULL)
         )
        SET mv.Status_warehouse = 'Дефицит склада',
            mv.updated_at = NOW(),
            mv.updated_by = CASE
                               WHEN mv.updated_by IS NULL OR TRIM(COALESCE(mv.updated_by, '')) = '' THEN 'ch_purch_to_wh'
                               ELSE CONCAT(mv.updated_by, '; ', 'ch_purch_to_wh')
                            END
        WHERE mv.type = 'move'
          AND mv.Status_warehouse = 'Ожидание закупки';

        UPDATE `Main` m
        JOIN (
            SELECT
                x.ERP_ID,
                SUM(x.Quantity_change) AS total_qty,
                MIN(CAST(t.Cost_total_rub AS DECIMAL(18, 6)) / NULLIF(ABS(t.Quantity_change), 0)) AS p_min,
                MAX(CAST(t.Cost_total_rub AS DECIMAL(18, 6)) / NULLIF(ABS(t.Quantity_change), 0)) AS p_max
            FROM tmp_purch_to_wh_ids x
            JOIN `Transactions` t ON t.id = x.id
            GROUP BY x.ERP_ID
        ) agg ON agg.ERP_ID = m.ERP_ID
        SET
            m.inProcess_purchase    = COALESCE(m.inProcess_purchase, 0) - agg.total_qty,
            m.Quantity_in_warehouse = COALESCE(m.Quantity_in_warehouse, 0) + agg.total_qty,
            m.Price_min               = LEAST(COALESCE(m.Price_min, agg.p_min), agg.p_min),
            m.Price_max               = GREATEST(COALESCE(m.Price_max, agg.p_max), agg.p_max),
            m.updated_at              = NOW(),
            m.updated_by              = 'ch_purch_to_wh';

        /* change: «В закупке» → «Норма», закрытие */
        UPDATE `Transactions` t
        INNER JOIN tmp_purch_to_wh_ids x ON x.id = t.id
        SET t.Status_warehouse   = 'Норма',
            t.Status_transaction = 'Исполнено',
            t.updated_at           = NOW(),
            t.updated_by           = CASE
                                        WHEN t.updated_by IS NULL OR TRIM(COALESCE(t.updated_by, '')) = '' THEN 'ch_purch_to_wh'
                                        ELSE CONCAT(t.updated_by, '; ', 'ch_purch_to_wh')
                                     END;

        DROP TEMPORARY TABLE IF EXISTS tmp_purch_erp_minid;
        DROP TEMPORARY TABLE IF EXISTS tmp_purch_to_wh_ids;

        COMMIT;
        DO RELEASE_LOCK('lock_ch_purch_to_wh');
    END IF;
END$$

DELIMITER ;
