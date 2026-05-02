-- ch_ownprod_to_wh: приёмка собственного производства на склад (change → Main, обновление связанных move).
-- Блокировка: lock_ch_ownProd_to_wh
--
-- Схема: новые поля Main (в т.ч. Quantity_of_rework с DEFAULT 0) в INSERT Main не перечисляются — срабатывают значения по умолчанию БД.
-- Новые реквизиты Transactions (Document_date, Order_sv, Rework_*, и т.д.) не создаются и в UPDATE change/move не сбрасываются, только статусы/updated_*.
--
-- Требования к БД: колонки Main.Source, Transactions.Source (sql/alter_Main_Source.sql, alter_transactions_Source.sql).
-- Значение «Разные» в Source не используется (как ch_purch_to_wh).
--
-- Source:
--   1) INSERT Main — если карточки по ERP_ID ещё нет;
--   2) UPDATE Main.Source — только если Main.Source пусто (NULL), из первой по id строки батча (допустимые значения — как в ENUM Main).
--
-- Отбор change: «В изготовлении», внешний или собственное производство → склад, Order_wh «Принято на склад», Order_prod «Изготовлено».
-- Связка с собственным изготовлением: Order_purch или Source = «Собственное производство» (как после ch_outside_to_ownProd).
-- GET_LOCK до 30 с.
--
-- #1137: во временной таблице нельзя дважды открыть её в одном операторе — tmp_ownprod_erp_minid (MIN(id) по ERP_ID);
-- закрытие change через отдельную TEMP tmp_ownprod_to_wh_pk только с id.

DELIMITER $$

DROP PROCEDURE IF EXISTS ch_ownprod_to_wh$$

CREATE PROCEDURE ch_ownprod_to_wh()
BEGIN
    DECLARE v_lock_ok INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR 3572, 1213, 1205
    BEGIN
        SET @erp_batch_blocked_message = 'Blocked: ch_ownprod_to_wh lock conflict';
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_ownprod_main_lock;
        DROP TEMPORARY TABLE IF EXISTS tmp_ownprod_tx_lock;
        IF v_lock_ok = 1 THEN
            DO RELEASE_LOCK('lock_ch_ownProd_to_wh');
        END IF;
    END;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_ownprod_main_lock;
        DROP TEMPORARY TABLE IF EXISTS tmp_ownprod_tx_lock;
        IF v_lock_ok = 1 THEN
            DO RELEASE_LOCK('lock_ch_ownProd_to_wh');
        END IF;
        RESIGNAL;
    END;

    SELECT GET_LOCK('lock_ch_ownProd_to_wh', 30) INTO v_lock_ok;


    IF COALESCE(v_lock_ok, 0) <> 1 THEN

        SET @erp_batch_blocked_message = 'Blocked: lock_ch_ownProd_to_wh lock is already held';

    END IF;

    IF v_lock_ok = 1 THEN
        START TRANSACTION;

        DROP TEMPORARY TABLE IF EXISTS tmp_ownprod_to_wh_ids;
        CREATE TEMPORARY TABLE tmp_ownprod_to_wh_ids (
            id INT UNSIGNED PRIMARY KEY,
            ERP_ID VARCHAR(255) NOT NULL,
            Advanced_group TEXT NULL,
            Quantity_change BIGINT NOT NULL
        );

        INSERT INTO tmp_ownprod_to_wh_ids (id, ERP_ID, Advanced_group, Quantity_change)
        SELECT
            t.id,
            t.ERP_ID,
            t.Advanced_group,
            COALESCE(t.Quantity_change, 0)
        FROM `Transactions` t
        WHERE t.type = 'change'
          AND COALESCE(t.Quantity_change, 0) > 0
          AND (
               t.Status_transaction IS NULL
            OR TRIM(COALESCE(t.Status_transaction, '')) = ''
            OR t.Status_transaction = 'В ожидании'
          )
          AND t.Status_warehouse = 'В изготовлении'
          AND t.where_from IN ('внешний', 'собственное производство')
          AND t.where_to = 'склад'
          AND (
               t.Order_purch = 'Собственное производство'
            OR t.Source = 'Собственное производство'
          )
          AND t.Order_wh = 'Принято на склад'
          AND t.Order_prod = 'Изготовлено';

        /* Берем row-lock по выбранным Transactions до любых изменений. Если строки заняты — выходим до следующего такта. */
        DROP TEMPORARY TABLE IF EXISTS tmp_ownprod_tx_lock;
        CREATE TEMPORARY TABLE tmp_ownprod_tx_lock (
            id INT UNSIGNED NOT NULL PRIMARY KEY
        );

        INSERT INTO tmp_ownprod_tx_lock (id)
        SELECT t.id
        FROM `Transactions` t
        INNER JOIN tmp_ownprod_to_wh_ids x ON x.id = t.id
        ORDER BY t.id
        FOR UPDATE NOWAIT;

        DROP TEMPORARY TABLE IF EXISTS tmp_ownprod_erp_minid;
        CREATE TEMPORARY TABLE tmp_ownprod_erp_minid (
            ERP_ID VARCHAR(255) NOT NULL,
            mid INT UNSIGNED NOT NULL,
            PRIMARY KEY (ERP_ID)
        );
        INSERT INTO tmp_ownprod_erp_minid (ERP_ID, mid)
        SELECT ERP_ID, MIN(id)
        FROM tmp_ownprod_to_wh_ids
        GROUP BY ERP_ID;

        /* ========== INSERT Main — нет строки по ERP_ID (первая по MIN(id) в батче) ========== */
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
            inProcess_manufacturing,
            Component_type,
            Part_material, Producer, Catalogue_number, Producer_article, Distributer,
            Distributer_article, MBOM_type, Mass_kg, Unit_of_measure, Height, Width, Length
        )
        SELECT
            NOW(),
            NOW(),
            'ch_ownprod_to_wh',
            'ch_ownprod_to_wh',
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
        FROM tmp_ownprod_to_wh_ids x
        INNER JOIN tmp_ownprod_erp_minid pick ON pick.ERP_ID = x.ERP_ID AND pick.mid = x.id
        INNER JOIN `Transactions` t ON t.id = x.id
        WHERE NOT EXISTS (
            SELECT 1
            FROM `Main` m
            WHERE m.ERP_ID = t.ERP_ID
        )
        GROUP BY t.ERP_ID;

        /* Берем row-lock по Main для всех ERP_ID батча до обновления Main и закрытия Transactions. */
        DROP TEMPORARY TABLE IF EXISTS tmp_ownprod_main_lock;
        CREATE TEMPORARY TABLE tmp_ownprod_main_lock (
            ERP_ID VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL PRIMARY KEY
        );

        INSERT INTO tmp_ownprod_main_lock (ERP_ID)
        SELECT m.ERP_ID
        FROM `Main` m
        INNER JOIN (
            SELECT DISTINCT ERP_ID
            FROM tmp_ownprod_to_wh_ids
        ) e ON e.ERP_ID COLLATE utf8mb4_unicode_ci = m.ERP_ID COLLATE utf8mb4_unicode_ci
        ORDER BY m.ERP_ID
        FOR UPDATE NOWAIT;

        /* ========== Main.Source — пусто: из Transactions.Source (первая строка батча по ERP_ID) ========== */
        UPDATE `Main` m
        INNER JOIN (
            SELECT
                x.ERP_ID,
                tx.`Source` AS src
            FROM tmp_ownprod_to_wh_ids x
            INNER JOIN `Transactions` tx ON tx.id = x.id
            INNER JOIN tmp_ownprod_erp_minid pick ON pick.ERP_ID = x.ERP_ID AND pick.mid = x.id
        ) fs ON fs.ERP_ID = m.ERP_ID
        SET
            m.`Source`     = fs.src,
            m.`updated_at` = NOW(),
            m.`updated_by` = 'ch_ownprod_to_wh'
        WHERE fs.src IS NOT NULL
          AND m.`Source` IS NULL
          AND fs.src IN ('Покупное', 'Собственное производство');

        /* move: «Ожидание изготовления» → «Дефицит склада» */
        UPDATE `Transactions` mv
        JOIN (
            SELECT DISTINCT ERP_ID, Advanced_group
            FROM tmp_ownprod_to_wh_ids
        ) g
          ON g.ERP_ID = mv.ERP_ID
         AND (
              (g.Advanced_group = mv.Advanced_group)
              OR (g.Advanced_group IS NULL AND mv.Advanced_group IS NULL)
         )
        SET mv.Status_warehouse = 'Дефицит склада',
            mv.updated_at = NOW(),
            mv.updated_by = CASE
                               WHEN mv.updated_by IS NULL OR TRIM(COALESCE(mv.updated_by, '')) = '' THEN 'ch_ownprod_to_wh'
                               ELSE CONCAT(mv.updated_by, '; ', 'ch_ownprod_to_wh')
                            END
        WHERE mv.type = 'move'
          AND (
               mv.Status_transaction IS NULL
            OR TRIM(COALESCE(mv.Status_transaction, '')) = ''
            OR mv.Status_transaction = 'В ожидании'
          )
          AND mv.Status_warehouse = 'Ожидание изготовления';

        UPDATE `Main` m
        JOIN (
            SELECT ERP_ID, SUM(Quantity_change) AS total_qty
            FROM tmp_ownprod_to_wh_ids
            GROUP BY ERP_ID
        ) agg ON agg.ERP_ID = m.ERP_ID
        SET
            m.inProcess_manufacturing = COALESCE(m.inProcess_manufacturing, 0) - agg.total_qty,
            m.Quantity_in_warehouse   = COALESCE(m.Quantity_in_warehouse, 0) + agg.total_qty,
            m.updated_at              = NOW(),
            m.updated_by              = 'ch_ownprod_to_wh';

        /* change: «В изготовлении» → «Норма», закрытие (#1137: TEMP только с id) */
        DROP TEMPORARY TABLE IF EXISTS tmp_ownprod_to_wh_pk;
        CREATE TEMPORARY TABLE tmp_ownprod_to_wh_pk (
            id INT UNSIGNED NOT NULL PRIMARY KEY
        );
        INSERT INTO tmp_ownprod_to_wh_pk (id)
        SELECT id FROM tmp_ownprod_to_wh_ids;

        UPDATE `Transactions` t
        INNER JOIN tmp_ownprod_to_wh_pk p ON p.id = t.id
        SET t.Status_warehouse   = 'Норма',
            t.Status_transaction = 'Исполнено',
            t.updated_at         = NOW(),
            t.updated_by = CASE
                              WHEN t.updated_by IS NULL OR TRIM(COALESCE(t.updated_by, '')) = '' THEN 'ch_ownprod_to_wh'
                              ELSE CONCAT(t.updated_by, '; ', 'ch_ownprod_to_wh')
                           END;

        DROP TEMPORARY TABLE IF EXISTS tmp_ownprod_to_wh_pk;
        DROP TEMPORARY TABLE IF EXISTS tmp_ownprod_main_lock;
        DROP TEMPORARY TABLE IF EXISTS tmp_ownprod_tx_lock;
        DROP TEMPORARY TABLE IF EXISTS tmp_ownprod_erp_minid;
        DROP TEMPORARY TABLE IF EXISTS tmp_ownprod_to_wh_ids;

        COMMIT;
        DO RELEASE_LOCK('lock_ch_ownProd_to_wh');
    END IF;
END$$

DELIMITER ;
