-- ch_toPurch_inPurchorPayed: change «внешний → закупка» при «В закупке»/«Оплачено» (без фильтра по Order_prod).
-- Для сценария «передача в закупку» с Order_prod = «В закупку» используйте ch_outside_to_purch.sql.
-- Блокировка: lock_process_purchase_change_to_main

DROP PROCEDURE IF EXISTS ch_toPurch_inPurchorPayed;

CREATE PROCEDURE ch_toPurch_inPurchorPayed()
BEGIN
    DECLARE v_lock_ok INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        IF v_lock_ok = 1 THEN
            DO RELEASE_LOCK('lock_process_purchase_change_to_main');
        END IF;
        RESIGNAL;
    END;

    /* Защита от параллельного запуска */
    SELECT GET_LOCK('lock_process_purchase_change_to_main', 0) INTO v_lock_ok;

    IF COALESCE(v_lock_ok, 0) <> 1 THEN
        SET @erp_batch_blocked_message = 'Blocked: lock_process_purchase_change_to_main lock is already held';
    END IF;

    IF COALESCE(v_lock_ok, 0) <> 1 THEN
        SET @erp_batch_blocked_message = 'Blocked: lock_process_purchase_change_to_main lock is already held';
    END IF;

    IF v_lock_ok = 1 THEN
        START TRANSACTION;

        DROP TEMPORARY TABLE IF EXISTS tmp_purch_change_ids;
        CREATE TEMPORARY TABLE tmp_purch_change_ids (
            id INT UNSIGNED PRIMARY KEY,
            ERP_ID VARCHAR(255) NOT NULL,
            Advanced_group TEXT NULL,
            Quantity_change BIGINT NOT NULL
        );

        INSERT INTO tmp_purch_change_ids (id, ERP_ID, Advanced_group, Quantity_change)
        SELECT
            t.id,
            t.ERP_ID,
            t.Advanced_group,
            COALESCE(t.Quantity_change, 0)
        FROM `Transactions` t
        WHERE NOT (t.Status_warehouse <=> 'В закупке')
          AND t.Order_purch IN ('В закупке', 'Оплачено')
          AND t.type = 'change'
          AND t.where_from = 'внешний'
          AND t.where_to = 'закупка';

        UPDATE `Main` AS m
        JOIN (
            SELECT
                ERP_ID,
                SUM(Quantity_change) AS total_quantity_change
            FROM tmp_purch_change_ids
            GROUP BY ERP_ID
        ) AS agg ON m.ERP_ID = agg.ERP_ID
        SET
            m.inProcess_purchase = COALESCE(m.inProcess_purchase, 0) + agg.total_quantity_change,
            m.updated_at         = NOW(),
            m.updated_by         = 'ch_toPurch_inPurchorPayed';

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
            'ch_toPurch_inPurchorPayed',
            'ch_toPurch_inPurchorPayed',
            t.ERP_ID,
            MIN(t.Supplied_component_number),
            MIN(t.Component_revision),
            MIN(t.Component_name),
            MIN(COALESCE(t.Components_quantity_in_assembly, 0)),
            SUM(COALESCE(t.Quantity_change, 0)),
            MIN(t.Component_type),
            MIN(t.Part_material), MIN(t.Producer), MIN(t.Catalogue_number), MIN(t.Producer_article),
            MIN(t.Distributer), MIN(t.Distributer_article), MIN(t.MBOM_type), MIN(t.Mass_kg),
            MIN(t.Unit_of_measure), MIN(t.Height), MIN(t.Width), MIN(t.Length)
        FROM `Transactions` t
        JOIN tmp_purch_change_ids x ON x.id = t.id
        WHERE NOT EXISTS (
            SELECT 1
            FROM `Main` m
            WHERE m.ERP_ID = t.ERP_ID
        )
        GROUP BY t.ERP_ID;

        UPDATE `Transactions` mv
        JOIN (
            SELECT DISTINCT ERP_ID, Advanced_group
            FROM tmp_purch_change_ids
        ) g
          ON g.ERP_ID = mv.ERP_ID
         AND (
              (g.Advanced_group = mv.Advanced_group)
              OR (g.Advanced_group IS NULL AND mv.Advanced_group IS NULL)
         )
        SET mv.Status_warehouse = 'Дефицит склада',
            mv.updated_at = NOW(),
            mv.updated_by = 'ch_toPurch_inPurchorPayed'
        WHERE mv.type = 'move'
          AND mv.Status_warehouse = 'Ожидание закупки';

        UPDATE `Transactions` t
        JOIN tmp_purch_change_ids x ON x.id = t.id
        SET t.Status_transaction = 'В ожидании',
            t.Status_warehouse = 'В закупке',
            t.updated_at = NOW(),
            t.updated_by = 'ch_toPurch_inPurchorPayed'
        WHERE x.Quantity_change > 0;

        UPDATE `Transactions` t
        JOIN tmp_purch_change_ids x ON x.id = t.id
        SET t.Status_transaction = 'Исполнено',
            t.Status_warehouse = 'Норма',
            t.updated_at = NOW(),
            t.updated_by = 'ch_toPurch_inPurchorPayed'
        WHERE x.Quantity_change < 0;

        DROP TEMPORARY TABLE IF EXISTS tmp_purch_change_ids;

        COMMIT;
        DO RELEASE_LOCK('lock_process_purchase_change_to_main');
    END IF;
END;
