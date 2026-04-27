-- move_kit_to_shopfloor: перенос из комплектации (kitting) по move склад→брак / отгрузка / изделие.
-- Блокировка: lock_move_wh_to_shopfloor (как в вашем скрипте; при параллели с move_wh_to_shopfloor учитывайте конфликт имён блокировки).
-- Лог: proc_transaction_move_log (level, message, tx_id, erp_id).
--
-- Вход: Status_warehouse = Комплектация, Order_wh = Списано со склада, Order_prod = Принято со склада.
-- Транзакция не завершается (остаётся «В ожидании»), Status_warehouse после обработки:
--   брак → Утилизация, отгрузка → Упаковка, изделие → Сборка.
-- Цель «цех» не обрабатывается (для неё — другие процедуры).

DELIMITER $$

DROP PROCEDURE IF EXISTS move_kit_to_shopfloor$$

CREATE PROCEDURE move_kit_to_shopfloor()
BEGIN
    DECLARE done INT DEFAULT 0;
    DECLARE v_lock_ok INT DEFAULT 0;

    DECLARE v_tx_id INT;
    DECLARE v_erp_id VARCHAR(255);
    DECLARE v_req_qty BIGINT;
    DECLARE v_where_to VARCHAR(32);

    DECLARE v_kit_qty BIGINT DEFAULT 0;
    DECLARE v_main_cnt INT DEFAULT 0;
    DECLARE v_move_qty BIGINT DEFAULT 0;
    DECLARE v_remain_qty BIGINT DEFAULT 0;

    DECLARE v_last_tx_id INT DEFAULT NULL;
    DECLARE v_last_erp_id VARCHAR(255) DEFAULT NULL;

    DECLARE cur CURSOR FOR
        SELECT t.id, t.ERP_ID, t.Quantity_of_parts_total, t.where_to
        FROM `Transactions` t
        WHERE t.type = 'move'
          AND t.where_from = 'склад'
          AND t.where_to IN ('брак', 'отгрузка', 'изделие')
          AND (t.Status_transaction IS NULL OR t.Status_transaction = 'В ожидании')
          AND t.Status_warehouse = 'Комплектация'
          AND t.Order_wh = 'Списано со склада'
          AND t.Order_prod = 'Принято со склада'
        ORDER BY t.ERP_ID, t.id;

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        INSERT INTO `proc_transaction_move_log` (`level`, `message`, `tx_id`, `erp_id`)
        VALUES ('ERROR', 'SQLEXCEPTION in move_kit_to_shopfloor', v_last_tx_id, v_last_erp_id);
        IF v_lock_ok = 1 THEN
            DO RELEASE_LOCK('lock_move_wh_to_shopfloor');
        END IF;
        RESIGNAL;
    END;

    SELECT GET_LOCK('lock_move_wh_to_shopfloor', 0) INTO v_lock_ok;

    IF v_lock_ok <> 1 THEN
        INSERT INTO `proc_transaction_move_log` (`level`, `message`)
        VALUES ('WARN', 'Procedure skipped: another instance is already running');
    ELSE
        OPEN cur;

        read_loop: LOOP
            FETCH cur INTO v_tx_id, v_erp_id, v_req_qty, v_where_to;
            IF done = 1 THEN
                LEAVE read_loop;
            END IF;

            SET v_last_tx_id = v_tx_id;
            SET v_last_erp_id = v_erp_id;

            START TRANSACTION;

            /* Один ряд + COUNT: без NOT FOUND; отделяем «нет строки Main» от «0 в комплектации» */
            SELECT
                COALESCE(MAX(m.Quantity_in_kitting), 0),
                COUNT(*)
            INTO v_kit_qty, v_main_cnt
            FROM `Main` m
            WHERE m.ERP_ID = v_erp_id;

            IF v_main_cnt = 0 THEN
                UPDATE `Transactions`
                   SET Status_warehouse   = 'Дефицит склада',
                       Status_transaction = 'В ожидании',
                       linked_transaction = v_tx_id,
                       updated_at       = CURRENT_TIMESTAMP
                 WHERE id = v_tx_id;

                INSERT INTO `proc_transaction_move_log` (`level`, `message`, `tx_id`, `erp_id`)
                VALUES ('WARN', 'ERP_ID not found in Main; set Status_warehouse=Дефицит склада', v_tx_id, v_erp_id);

                COMMIT;
                ITERATE read_loop;
            END IF;

            IF v_kit_qty = 0 THEN
                UPDATE `Transactions`
                   SET Status_warehouse   = 'Дефицит склада',
                       Status_transaction = 'В ожидании',
                       linked_transaction = v_tx_id,
                       updated_at         = CURRENT_TIMESTAMP
                 WHERE id = v_tx_id;

                COMMIT;
                ITERATE read_loop;
            END IF;

            IF v_kit_qty >= v_req_qty THEN
                UPDATE `Main`
                   SET Quantity_in_kitting   = Quantity_in_kitting - v_req_qty,
                       Quantity_on_shopfloor = COALESCE(Quantity_on_shopfloor, 0) + v_req_qty,
                       updated_at            = CURRENT_TIMESTAMP
                 WHERE ERP_ID = v_erp_id;

                UPDATE `Transactions`
                   SET Status_transaction = 'В ожидании',
                       Status_warehouse   = CASE v_where_to
                           WHEN 'брак' THEN 'Утилизация'
                           WHEN 'отгрузка' THEN 'Упаковка'
                           WHEN 'изделие' THEN 'Сборка'
                           ELSE 'Норма'
                       END,
                       linked_transaction = v_tx_id,
                       updated_at         = CURRENT_TIMESTAMP
                 WHERE id = v_tx_id;

                COMMIT;
                ITERATE read_loop;
            END IF;

            SET v_move_qty = v_kit_qty;
            SET v_remain_qty = v_req_qty - v_kit_qty;

            UPDATE `Transactions`
               SET Status_transaction = 'Заменено',
                   Status_warehouse   = 'Норма',
                   linked_transaction = v_tx_id,
                   updated_at         = CURRENT_TIMESTAMP
             WHERE id = v_tx_id;

            INSERT INTO `Transactions` (
                ERP_ID, created_at, updated_at, created_by, updated_by,
                linked_transaction, type, where_from, where_to,
                Quantity_of_parts_total, Quantity_change, Status_transaction,
                Project, Target_assembly, Supplied_component_number, Component_revision, Component_name,
                Quantity_in_target_assembly, Quantity_of_target_assemblies, Components_quantity_in_assembly,
                Component_type, For_supplied_as_assembly_components_provided_by_supplier,
                Part_material, Producer, Catalogue_number, Producer_article, Distributer, Distributer_article,
                MBOM_type, Mass_kg, Unit_of_measure, Height, Width, Length,
                Advanced_group, Address,
                Document_no, Zakaz_no, Date_needed, Date_expected, Cost_total_rub,
                Supplier, Location, Source, Initial_doc_no,
                Order_purch, Order_wh, Order_prod, Order_OTK,
                Status_warehouse
            )
            SELECT
                ERP_ID, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 'move_kit_to_shopfloor', COALESCE(updated_by, 'move_kit_to_shopfloor'),
                v_tx_id, 'move', where_from, where_to,
                v_move_qty, 0, 'В ожидании',
                Project, Target_assembly, Supplied_component_number, Component_revision, Component_name,
                Quantity_in_target_assembly, Quantity_of_target_assemblies, Components_quantity_in_assembly,
                Component_type, For_supplied_as_assembly_components_provided_by_supplier,
                Part_material, Producer, Catalogue_number, Producer_article, Distributer, Distributer_article,
                MBOM_type, Mass_kg, Unit_of_measure, Height, Width, Length,
                Advanced_group, Address,
                Document_no, Zakaz_no, Date_needed, Date_expected, Cost_total_rub,
                Supplier, Location, Source, Initial_doc_no,
                Order_purch, Order_wh, Order_prod, Order_OTK,
                CASE where_to
                    WHEN 'брак' THEN 'Утилизация'
                    WHEN 'отгрузка' THEN 'Упаковка'
                    WHEN 'изделие' THEN 'Сборка'
                    ELSE 'Норма'
                END
            FROM `Transactions`
            WHERE id = v_tx_id;

            INSERT INTO `Transactions` (
                ERP_ID, created_at, updated_at, created_by, updated_by,
                linked_transaction, type, where_from, where_to,
                Quantity_of_parts_total, Quantity_change, Status_transaction,
                Project, Target_assembly, Supplied_component_number, Component_revision, Component_name,
                Quantity_in_target_assembly, Quantity_of_target_assemblies, Components_quantity_in_assembly,
                Component_type, For_supplied_as_assembly_components_provided_by_supplier,
                Part_material, Producer, Catalogue_number, Producer_article, Distributer, Distributer_article,
                MBOM_type, Mass_kg, Unit_of_measure, Height, Width, Length,
                Advanced_group, Address,
                Document_no, Zakaz_no, Date_needed, Date_expected, Cost_total_rub,
                Supplier, Location, Source, Initial_doc_no,
                Order_purch, Order_wh, Order_prod, Order_OTK,
                Status_warehouse
            )
            SELECT
                ERP_ID, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 'move_kit_to_shopfloor', COALESCE(updated_by, 'move_kit_to_shopfloor'),
                v_tx_id, 'move', 'склад', where_to,
                v_remain_qty, 0, 'В ожидании',
                Project, Target_assembly, Supplied_component_number, Component_revision, Component_name,
                Quantity_in_target_assembly, Quantity_of_target_assemblies, Components_quantity_in_assembly,
                Component_type, For_supplied_as_assembly_components_provided_by_supplier,
                Part_material, Producer, Catalogue_number, Producer_article, Distributer, Distributer_article,
                MBOM_type, Mass_kg, Unit_of_measure, Height, Width, Length,
                Advanced_group, Address,
                Document_no, Zakaz_no, Date_needed, Date_expected, Cost_total_rub,
                Supplier, Location, Source, Initial_doc_no,
                Order_purch, Order_wh, Order_prod, Order_OTK,
                'Дефицит склада'
            FROM `Transactions`
            WHERE id = v_tx_id;

            UPDATE `Main`
               SET Quantity_in_kitting   = Quantity_in_kitting - v_move_qty,
                   Quantity_on_shopfloor = COALESCE(Quantity_on_shopfloor, 0) + v_move_qty,
                   updated_at            = CURRENT_TIMESTAMP
             WHERE ERP_ID = v_erp_id;

            COMMIT;
        END LOOP;

        CLOSE cur;
        DO RELEASE_LOCK('lock_move_wh_to_shopfloor');
    END IF;
END$$

DELIMITER ;
