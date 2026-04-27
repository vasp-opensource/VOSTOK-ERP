-- deficit_wh: упрощенная обработка move со склада
-- Вход:
--   type='move',
--   where_from='склад',
--   where_to in ('брак','отгрузка','изделие'),
--   Status_transaction='В ожидании',
--   Status_warehouse='Новая'
--
-- Логика:
-- 1) Родительская строка всегда закрывается (Status_transaction='Заменено').
-- 2) Если складского количества хватает: создается дочерний move со статусом комплектации,
--    количество списывается в Main.Quantity_in_kitting.
-- 3) Если складского количества нет, но ожидаемого поступления хватает:
--    создается дочерний move со статусом склада "Дефицит поставки".
-- 4) Если складского количества частично хватает:
--    первая дочерняя строка на складскую часть (как в п.2),
--    вторая дочерняя строка на остаток (как в п.3).

DROP PROCEDURE IF EXISTS deficit_wh;

DELIMITER $$

CREATE PROCEDURE deficit_wh()
BEGIN
    DECLARE done INT DEFAULT 0;
    DECLARE v_lock_ok INT DEFAULT 0;

    DECLARE v_tx_id INT;
    DECLARE v_erp_id VARCHAR(255);
    DECLARE v_req_qty BIGINT;

    DECLARE v_stock BIGINT DEFAULT 0;
    DECLARE v_expect_purch BIGINT DEFAULT 0;
    DECLARE v_expect_prod BIGINT DEFAULT 0;
    DECLARE v_wait_supply BIGINT DEFAULT 0;
    DECLARE v_need_supply BIGINT DEFAULT 0;
    DECLARE v_need_purch BIGINT DEFAULT 0;
    DECLARE v_need_prod BIGINT DEFAULT 0;
    DECLARE v_expected_used BIGINT DEFAULT 0;

    DECLARE v_expected_avail BIGINT DEFAULT 0;
    DECLARE v_total_avail BIGINT DEFAULT 0;

    DECLARE v_part_stock BIGINT DEFAULT 0;
    DECLARE v_part_rest BIGINT DEFAULT 0;

    DECLARE v_status_wh_kitting VARCHAR(64) DEFAULT 'В комплектации';
    DECLARE v_status_wh_deficit VARCHAR(64) DEFAULT 'Дефицит поставки';
    DECLARE v_status_tx_new VARCHAR(64) DEFAULT 'Новая';

    DECLARE cur CURSOR FOR
        SELECT t.id, t.ERP_ID, COALESCE(t.Quantity_of_parts_total, 0) AS req_qty
        FROM `Transactions` t
        WHERE t.type = 'move'
          AND t.where_from = 'склад'
          AND t.where_to IN ('брак', 'отгрузка', 'изделие')
          AND t.Status_transaction = 'В ожидании'
          AND t.Status_warehouse = 'Новая'
        ORDER BY
            t.ERP_ID,
            CASE t.where_to
                WHEN 'брак' THEN 1
                WHEN 'отгрузка' THEN 2
                WHEN 'изделие' THEN 3
                ELSE 4
            END,
            t.id;

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        IF v_lock_ok = 1 THEN
            DO RELEASE_LOCK('lock_process_move_deficit_wh_to_shop');
        END IF;
        RESIGNAL;
    END;

    SELECT GET_LOCK('lock_process_move_deficit_wh_to_shop', 0) INTO v_lock_ok;

    IF v_lock_ok = 1 THEN
        START TRANSACTION;

        -- Подгоняем статусы под фактический enum в текущей БД.
        IF NOT EXISTS (
            SELECT 1
            FROM INFORMATION_SCHEMA.COLUMNS c
            WHERE c.TABLE_SCHEMA = DATABASE()
              AND c.TABLE_NAME = 'Transactions'
              AND c.COLUMN_NAME = 'Status_warehouse'
              AND c.COLUMN_TYPE LIKE '%''В комплектации''%'
        ) THEN
            SET v_status_wh_kitting = 'Комплектация';
        END IF;

        IF NOT EXISTS (
            SELECT 1
            FROM INFORMATION_SCHEMA.COLUMNS c
            WHERE c.TABLE_SCHEMA = DATABASE()
              AND c.TABLE_NAME = 'Transactions'
              AND c.COLUMN_NAME = 'Status_warehouse'
              AND c.COLUMN_TYPE LIKE '%''Дефицит поставки''%'
        ) THEN
            SET v_status_wh_deficit = 'Дефицит склада';
        END IF;

        IF NOT EXISTS (
            SELECT 1
            FROM INFORMATION_SCHEMA.COLUMNS c
            WHERE c.TABLE_SCHEMA = DATABASE()
              AND c.TABLE_NAME = 'Transactions'
              AND c.COLUMN_NAME = 'Status_transaction'
              AND c.COLUMN_TYPE LIKE '%''Новая''%'
        ) THEN
            SET v_status_tx_new = 'В ожидании';
        END IF;

        DROP TEMPORARY TABLE IF EXISTS tmp_deficit_wh_expected_used;
        CREATE TEMPORARY TABLE tmp_deficit_wh_expected_used (
            erp_id VARCHAR(255) NOT NULL PRIMARY KEY,
            used_qty BIGINT NOT NULL DEFAULT 0
        );

        OPEN cur;

        read_loop: LOOP
            FETCH cur INTO v_tx_id, v_erp_id, v_req_qty;
            IF done = 1 THEN
                LEAVE read_loop;
            END IF;

            SET v_req_qty = GREATEST(COALESCE(v_req_qty, 0), 0);

            SET v_stock = COALESCE((
                SELECT m.Quantity_in_warehouse
                FROM `Main` m
                WHERE m.ERP_ID = v_erp_id
                LIMIT 1
            ), 0);

            SELECT COALESCE(SUM(COALESCE(t.Quantity_change, 0)), 0)
              INTO v_expect_purch
            FROM `Transactions` t
            WHERE t.ERP_ID = v_erp_id
              AND t.type = 'change'
              AND t.where_from = 'внешний'
              AND t.where_to = 'склад'
              AND t.Status_transaction = 'В ожидании'
              AND t.Status_warehouse = 'В закупке';

            SELECT COALESCE(SUM(COALESCE(t.Quantity_change, 0)), 0)
              INTO v_expect_prod
            FROM `Transactions` t
            WHERE t.ERP_ID = v_erp_id
              AND t.type = 'change'
              AND t.where_from = 'внешний'
              AND t.where_to = 'склад'
              AND t.Status_transaction = 'В ожидании'
              AND t.Status_warehouse = 'В изготовлении';

            SELECT COALESCE(SUM(COALESCE(t.Quantity_change, 0)), 0)
              INTO v_wait_supply
            FROM `Transactions` t
            WHERE t.ERP_ID = v_erp_id
              AND t.type = 'change'
              AND t.where_from = 'внешний'
              AND t.where_to = 'склад'
              AND t.Status_transaction = 'В ожидании'
              AND t.Status_warehouse = 'Новая';

            SELECT COALESCE(SUM(COALESCE(t.Quantity_of_parts_total, 0)), 0)
              INTO v_need_supply
            FROM `Transactions` t
            WHERE t.ERP_ID = v_erp_id
              AND t.type = 'move'
              AND t.where_from = 'склад'
              AND t.where_to IN ('брак', 'отгрузка', 'изделие')
              AND t.Status_transaction = 'В ожидании'
              AND t.Status_warehouse IN ('Новая', 'Ожидание поставки');

            SELECT COALESCE(SUM(COALESCE(t.Quantity_of_parts_total, 0)), 0)
              INTO v_need_purch
            FROM `Transactions` t
            WHERE t.ERP_ID = v_erp_id
              AND t.type = 'move'
              AND t.Status_transaction = 'В ожидании'
              AND t.Status_warehouse = 'Ожидание закупки';

            SELECT COALESCE(SUM(COALESCE(t.Quantity_of_parts_total, 0)), 0)
              INTO v_need_prod
            FROM `Transactions` t
            WHERE t.ERP_ID = v_erp_id
              AND t.type = 'move'
              AND t.Status_transaction = 'В ожидании'
              AND t.Status_warehouse = 'Ожидание изготовления';

            SET v_expected_used = COALESCE((
                SELECT u.used_qty
                FROM tmp_deficit_wh_expected_used u
                WHERE u.erp_id = v_erp_id
                LIMIT 1
            ), 0);

            SET v_expected_avail =
                (v_expect_purch - v_need_purch)
              + (v_expect_prod - v_need_prod)
              + (v_wait_supply - v_need_supply)
              - v_expected_used;

            SET v_expected_avail = GREATEST(v_expected_avail, 0);
            SET v_total_avail = GREATEST(v_stock, 0) + v_expected_avail;

            UPDATE `Transactions`
               SET Status_transaction = 'Заменено',
                   linked_transaction = v_tx_id,
                   Status_warehouse   = 'Норма',
                   updated_by         = 'deficit_wh',
                   updated_at         = CURRENT_TIMESTAMP
             WHERE id = v_tx_id;

            IF v_req_qty > 0 THEN
                IF v_stock >= v_req_qty THEN
                    INSERT INTO `Transactions` (
                        ERP_ID, created_at, updated_at, created_by, updated_by, linked_transaction,
                        type, where_from, where_to, Quantity_of_parts_total, Quantity_change, Status_transaction,
                        Project, Target_assembly, Supplied_component_number, Component_revision, Component_name,
                        Quantity_in_target_assembly, Quantity_of_target_assemblies, Components_quantity_in_assembly, Component_type,
                        For_supplied_as_assembly_components_provided_by_supplier, Part_material, Producer, Catalogue_number,
                        Producer_article, Distributer, Distributer_article, MBOM_type, Mass_kg, Unit_of_measure,
                        Height, Width, Length, Advanced_group, Address, Order_purch, Order_wh, Order_prod, Order_OTK,
                        Status_warehouse, Document_no, Zakaz_no, Date_needed, Date_expected, Cost_total_rub
                    )
                    SELECT
                        t.ERP_ID, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 'deficit_wh', 'deficit_wh', v_tx_id,
                        'move', t.where_from, t.where_to, v_req_qty, 0, 'В ожидании',
                        t.Project, t.Target_assembly, t.Supplied_component_number, t.Component_revision, t.Component_name,
                        t.Quantity_in_target_assembly, t.Quantity_of_target_assemblies, t.Components_quantity_in_assembly, t.Component_type,
                        t.For_supplied_as_assembly_components_provided_by_supplier, t.Part_material, t.Producer, t.Catalogue_number,
                        t.Producer_article, t.Distributer, t.Distributer_article, t.MBOM_type, t.Mass_kg, t.Unit_of_measure,
                        t.Height, t.Width, t.Length, t.Advanced_group, t.Address, t.Order_purch, 'В комплектации', t.Order_prod, t.Order_OTK,
                        v_status_wh_kitting, t.Document_no, t.Zakaz_no, t.Date_needed, t.Date_expected, t.Cost_total_rub
                    FROM `Transactions` t
                    WHERE t.id = v_tx_id;

                    UPDATE `Main`
                       SET Quantity_in_warehouse = COALESCE(Quantity_in_warehouse, 0) - v_req_qty,
                           Quantity_in_kitting   = COALESCE(Quantity_in_kitting, 0) + v_req_qty,
                           updated_by            = 'deficit_wh',
                           updated_at            = CURRENT_TIMESTAMP
                     WHERE ERP_ID = v_erp_id;
                ELSEIF v_stock = 0 AND v_expected_avail >= v_req_qty THEN
                    INSERT INTO `Transactions` (
                        ERP_ID, created_at, updated_at, created_by, updated_by, linked_transaction,
                        type, where_from, where_to, Quantity_of_parts_total, Quantity_change, Status_transaction,
                        Project, Target_assembly, Supplied_component_number, Component_revision, Component_name,
                        Quantity_in_target_assembly, Quantity_of_target_assemblies, Components_quantity_in_assembly, Component_type,
                        For_supplied_as_assembly_components_provided_by_supplier, Part_material, Producer, Catalogue_number,
                        Producer_article, Distributer, Distributer_article, MBOM_type, Mass_kg, Unit_of_measure,
                        Height, Width, Length, Advanced_group, Address, Order_purch, Order_wh, Order_prod, Order_OTK,
                        Status_warehouse, Document_no, Zakaz_no, Date_needed, Date_expected, Cost_total_rub
                    )
                    SELECT
                        t.ERP_ID, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 'deficit_wh', 'deficit_wh', v_tx_id,
                        'move', t.where_from, t.where_to, v_req_qty, 0, v_status_tx_new,
                        t.Project, t.Target_assembly, t.Supplied_component_number, t.Component_revision, t.Component_name,
                        t.Quantity_in_target_assembly, t.Quantity_of_target_assemblies, t.Components_quantity_in_assembly, t.Component_type,
                        t.For_supplied_as_assembly_components_provided_by_supplier, t.Part_material, t.Producer, t.Catalogue_number,
                        t.Producer_article, t.Distributer, t.Distributer_article, t.MBOM_type, t.Mass_kg, t.Unit_of_measure,
                        t.Height, t.Width, t.Length, t.Advanced_group, t.Address, t.Order_purch, t.Order_wh, t.Order_prod, t.Order_OTK,
                        v_status_wh_deficit, t.Document_no, t.Zakaz_no, t.Date_needed, t.Date_expected, t.Cost_total_rub
                    FROM `Transactions` t
                    WHERE t.id = v_tx_id;

                    INSERT INTO tmp_deficit_wh_expected_used (erp_id, used_qty)
                    VALUES (v_erp_id, v_req_qty)
                    ON DUPLICATE KEY UPDATE used_qty = used_qty + VALUES(used_qty);
                ELSEIF v_stock < v_req_qty THEN
                    SET v_part_stock = GREATEST(v_stock, 0);
                    SET v_part_rest = v_req_qty - v_part_stock;

                    IF v_part_stock > 0 THEN
                        INSERT INTO `Transactions` (
                            ERP_ID, created_at, updated_at, created_by, updated_by, linked_transaction,
                            type, where_from, where_to, Quantity_of_parts_total, Quantity_change, Status_transaction,
                            Project, Target_assembly, Supplied_component_number, Component_revision, Component_name,
                            Quantity_in_target_assembly, Quantity_of_target_assemblies, Components_quantity_in_assembly, Component_type,
                            For_supplied_as_assembly_components_provided_by_supplier, Part_material, Producer, Catalogue_number,
                            Producer_article, Distributer, Distributer_article, MBOM_type, Mass_kg, Unit_of_measure,
                            Height, Width, Length, Advanced_group, Address, Order_purch, Order_wh, Order_prod, Order_OTK,
                            Status_warehouse, Document_no, Zakaz_no, Date_needed, Date_expected, Cost_total_rub
                        )
                        SELECT
                            t.ERP_ID, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 'deficit_wh', 'deficit_wh', v_tx_id,
                            'move', t.where_from, t.where_to, v_part_stock, 0, 'В ожидании',
                            t.Project, t.Target_assembly, t.Supplied_component_number, t.Component_revision, t.Component_name,
                            t.Quantity_in_target_assembly, t.Quantity_of_target_assemblies, t.Components_quantity_in_assembly, t.Component_type,
                            t.For_supplied_as_assembly_components_provided_by_supplier, t.Part_material, t.Producer, t.Catalogue_number,
                            t.Producer_article, t.Distributer, t.Distributer_article, t.MBOM_type, t.Mass_kg, t.Unit_of_measure,
                            t.Height, t.Width, t.Length, t.Advanced_group, t.Address, t.Order_purch, 'В комплектации', t.Order_prod, t.Order_OTK,
                            v_status_wh_kitting, t.Document_no, t.Zakaz_no, t.Date_needed, t.Date_expected, t.Cost_total_rub
                        FROM `Transactions` t
                        WHERE t.id = v_tx_id;

                        UPDATE `Main`
                           SET Quantity_in_warehouse = COALESCE(Quantity_in_warehouse, 0) - v_part_stock,
                               Quantity_in_kitting   = COALESCE(Quantity_in_kitting, 0) + v_part_stock,
                               updated_by            = 'deficit_wh',
                               updated_at            = CURRENT_TIMESTAMP
                         WHERE ERP_ID = v_erp_id;
                    END IF;

                    IF v_part_rest > 0 THEN
                        INSERT INTO `Transactions` (
                            ERP_ID, created_at, updated_at, created_by, updated_by, linked_transaction,
                            type, where_from, where_to, Quantity_of_parts_total, Quantity_change, Status_transaction,
                            Project, Target_assembly, Supplied_component_number, Component_revision, Component_name,
                            Quantity_in_target_assembly, Quantity_of_target_assemblies, Components_quantity_in_assembly, Component_type,
                            For_supplied_as_assembly_components_provided_by_supplier, Part_material, Producer, Catalogue_number,
                            Producer_article, Distributer, Distributer_article, MBOM_type, Mass_kg, Unit_of_measure,
                            Height, Width, Length, Advanced_group, Address, Order_purch, Order_wh, Order_prod, Order_OTK,
                            Status_warehouse, Document_no, Zakaz_no, Date_needed, Date_expected, Cost_total_rub
                        )
                        SELECT
                            t.ERP_ID, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 'deficit_wh', 'deficit_wh', v_tx_id,
                            'move', t.where_from, t.where_to, v_part_rest, 0, v_status_tx_new,
                            t.Project, t.Target_assembly, t.Supplied_component_number, t.Component_revision, t.Component_name,
                            t.Quantity_in_target_assembly, t.Quantity_of_target_assemblies, t.Components_quantity_in_assembly, t.Component_type,
                            t.For_supplied_as_assembly_components_provided_by_supplier, t.Part_material, t.Producer, t.Catalogue_number,
                            t.Producer_article, t.Distributer, t.Distributer_article, t.MBOM_type, t.Mass_kg, t.Unit_of_measure,
                            t.Height, t.Width, t.Length, t.Advanced_group, t.Address, t.Order_purch, t.Order_wh, t.Order_prod, t.Order_OTK,
                            v_status_wh_deficit, t.Document_no, t.Zakaz_no, t.Date_needed, t.Date_expected, t.Cost_total_rub
                        FROM `Transactions` t
                        WHERE t.id = v_tx_id;

                        INSERT INTO tmp_deficit_wh_expected_used (erp_id, used_qty)
                        VALUES (v_erp_id, v_part_rest)
                        ON DUPLICATE KEY UPDATE used_qty = used_qty + VALUES(used_qty);
                    END IF;
                END IF;
            END IF;
        END LOOP;

        CLOSE cur;
        DROP TEMPORARY TABLE IF EXISTS tmp_deficit_wh_expected_used;

        COMMIT;
        DO RELEASE_LOCK('lock_process_move_deficit_wh_to_shop');
    END IF;
END$$

DELIMITER ;
