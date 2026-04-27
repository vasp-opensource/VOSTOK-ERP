DROP PROCEDURE IF EXISTS import_do;

DELIMITER $$

CREATE PROCEDURE import_do()
BEGIN
    DECLARE v_lock_ok INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        IF v_lock_ok = 1 THEN
            DO RELEASE_LOCK('lock_process_import_do');
        END IF;
        RESIGNAL;
    END;

    SELECT GET_LOCK('lock_process_import_do', 0) INTO v_lock_ok;

    IF v_lock_ok = 1 THEN
        START TRANSACTION;

        /* Снимок входного набора: только исходные строки "Новая" */
        DROP TEMPORARY TABLE IF EXISTS tmp_import_do_initial_ids;
        CREATE TEMPORARY TABLE tmp_import_do_initial_ids (
            id INT UNSIGNED NOT NULL PRIMARY KEY
        );

        INSERT INTO tmp_import_do_initial_ids (id)
        SELECT i.id
        FROM `Import` i
        WHERE i.Status_import = 'Новая';

        /* 1) Order_import='Отменить' -> Status_import='Отменено' */
        UPDATE `Import` i
        INNER JOIN tmp_import_do_initial_ids s ON s.id = i.id
        SET
            i.Status_import = 'Отменено',
            i.updated_at = CURRENT_TIMESTAMP
        WHERE i.Order_import = 'Отменить'
          AND i.Status_import = 'Новая';

        /* 2) Suggestion='Отменить' AND Order_import='Выполнить' -> Status_import='Отменено' */
        UPDATE `Import` i
        INNER JOIN tmp_import_do_initial_ids s ON s.id = i.id
        SET
            i.Status_import = 'Отменено',
            i.updated_at = CURRENT_TIMESTAMP
        WHERE i.Suggestion = 'Отменить'
          AND i.Order_import = 'Выполнить'
          AND i.Status_import = 'Новая';

        /* 3a) Заменить + move (склад->брак/отгрузка/изделие) + Needed_new > 0:
               родителю Suggestion='Импортировать', создать дочернюю change внешний->склад */
        DROP TEMPORARY TABLE IF EXISTS tmp_import_do_replace_move;
        CREATE TEMPORARY TABLE tmp_import_do_replace_move AS
        SELECT
            i.id AS parent_id,
            COALESCE(i.Needed_new, 0) AS needed_new,
            COALESCE(i.Target_assembly, '') AS target_assembly_key,
            COALESCE(i.Advanced_group, '') AS adv_group_key,
            GREATEST(
                COALESCE(i.Needed_new, 0) - COALESCE(ic.accounted_qty, 0),
                0
            ) AS qty_to_create
        FROM `Import` i
        INNER JOIN tmp_import_do_initial_ids s ON s.id = i.id
        LEFT JOIN (
            SELECT
                z.`ERP_ID`,
                COALESCE(z.`Target_assembly`, '') AS target_assembly_key,
                COALESCE(z.`Advanced_group`, '') AS adv_group_key,
                SUM(COALESCE(z.`Quantity_change`, 0)) AS accounted_qty
            FROM `Import` z
            WHERE z.`type` = 'change'
              AND z.`where_from` = 'внешний'
              AND z.`where_to` = 'склад'
              AND z.`Status_import` = 'Новая'
            GROUP BY z.`ERP_ID`, COALESCE(z.`Target_assembly`, ''), COALESCE(z.`Advanced_group`, '')
        ) ic
          ON ic.`ERP_ID` COLLATE utf8mb4_unicode_ci = i.`ERP_ID` COLLATE utf8mb4_unicode_ci
         AND ic.target_assembly_key = COALESCE(i.`Target_assembly`, '')
         AND ic.adv_group_key = COALESCE(i.`Advanced_group`, '')
        WHERE i.Status_import = 'Новая'
          AND i.Suggestion = 'Заменить'
          AND i.Order_import = 'Выполнить'
          AND i.type = 'move'
          AND i.where_from = 'склад'
          AND i.where_to IN ('брак', 'отгрузка', 'изделие')
          AND (COALESCE(i.Needed_new, 0) - COALESCE(ic.accounted_qty, 0)) > 0;

        INSERT INTO `Import` (
            ERP_ID, created_at, updated_at, created_by, updated_by, linked_transaction,
            type, where_from, where_to, Quantity_of_parts_total, Quantity_change,
            Quantity_in_transactions, inProcess_purchase, inProcess_manufacturing,
            Quantity_in_warehouse, Quantity_in_kitting, Quantity_on_shopfloor,
            Quantity_implemented, Quantity_shipped, Quantity_of_losses, Quantity_avaliable, Needed_new,
            Can_be_cancelled_sure, Can_be_cancelled_maybe,
            Suggestion, Order_import, Status_import,
            Project, Target_assembly, Supplied_component_number, Component_revision, Component_name,
            Quantity_in_target_assembly, Quantity_of_target_assemblies, Component_type,
            For_supplied_as_assembly_components_provided_by_supplier, Components_quantity_in_assembly,
            Part_material, Producer, Catalogue_number, Producer_article, Distributer, Distributer_article,
            MBOM_type, Mass_kg, Unit_of_measure, Height, Width, Length, Advanced_group, Address,
            Document_no, Zakaz_no, Date_needed, Date_expected, Cost_total_rub,
            Supplier, Price_of_single_unit, Location, Source, Initial_doc_no
        )
        SELECT
            p.ERP_ID, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 'import_do', 'import_do', rm.parent_id,
            'change', 'внешний', 'склад', 0, rm.qty_to_create,
            p.Quantity_in_transactions, p.inProcess_purchase, p.inProcess_manufacturing,
            p.Quantity_in_warehouse, p.Quantity_in_kitting, p.Quantity_on_shopfloor,
            p.Quantity_implemented, p.Quantity_shipped, p.Quantity_of_losses, p.Quantity_avaliable, 0,
            p.Can_be_cancelled_sure, p.Can_be_cancelled_maybe,
            'Импортировать', 'Ожидание', 'Новая',
            p.Project, p.Target_assembly, p.Supplied_component_number, p.Component_revision, p.Component_name,
            p.Quantity_in_target_assembly, p.Quantity_of_target_assemblies, p.Component_type,
            p.For_supplied_as_assembly_components_provided_by_supplier, p.Components_quantity_in_assembly,
            p.Part_material, p.Producer, p.Catalogue_number, p.Producer_article, p.Distributer, p.Distributer_article,
            p.MBOM_type, p.Mass_kg, p.Unit_of_measure, p.Height, p.Width, p.Length, p.Advanced_group, p.Address,
            p.Document_no, p.Zakaz_no, p.Date_needed, p.Date_expected, p.Cost_total_rub,
            p.Supplier, p.Price_of_single_unit, p.Location, p.Source, p.Initial_doc_no
        FROM tmp_import_do_replace_move rm
        INNER JOIN `Import` p ON p.id = rm.parent_id;

        UPDATE `Import` i
        INNER JOIN tmp_import_do_replace_move rm ON rm.parent_id = i.id
        SET
            i.Suggestion = 'Импортировать',
            i.Order_import = 'Ожидание',
            i.Status_import = 'Новая',
            i.linked_transaction = i.id,
            i.updated_at = CURRENT_TIMESTAMP
        WHERE i.Status_import = 'Новая';

        DROP TEMPORARY TABLE IF EXISTS tmp_import_do_replace_move;

        /* 3b) Заменить + change внешний->склад + qty<0 + abs(qty)>(sure+maybe):
               родитель -> Отменено, создать 2 новые "Новая" */
        DROP TEMPORARY TABLE IF EXISTS tmp_import_do_replace_change;
        CREATE TEMPORARY TABLE tmp_import_do_replace_change AS
        SELECT
            i.id AS parent_id,
            COALESCE(i.Quantity_change, 0) AS parent_qty,
            (COALESCE(i.Can_be_cancelled_sure, 0) + COALESCE(i.Can_be_cancelled_maybe, 0)) AS can_total
        FROM `Import` i
        INNER JOIN tmp_import_do_initial_ids s ON s.id = i.id
        WHERE i.Status_import = 'Новая'
          AND i.Suggestion = 'Заменить'
          AND i.Order_import = 'Выполнить'
          AND i.type = 'change'
          AND i.where_from = 'внешний'
          AND i.where_to = 'склад'
          AND COALESCE(i.Quantity_change, 0) < 0
          AND ABS(COALESCE(i.Quantity_change, 0)) > (COALESCE(i.Can_be_cancelled_sure, 0) + COALESCE(i.Can_be_cancelled_maybe, 0));

        UPDATE `Import` i
        INNER JOIN tmp_import_do_replace_change rc ON rc.parent_id = i.id
        SET
            i.Status_import = 'Отменено',
            i.linked_transaction = i.id,
            i.updated_at = CURRENT_TIMESTAMP;

        /* Первая новая: qty = -1 * (sure + maybe), Suggestion='Импортировать' */
        INSERT INTO `Import` (
            ERP_ID, created_at, updated_at, created_by, updated_by, linked_transaction,
            type, where_from, where_to, Quantity_of_parts_total, Quantity_change,
            Quantity_in_transactions, inProcess_purchase, inProcess_manufacturing,
            Quantity_in_warehouse, Quantity_in_kitting, Quantity_on_shopfloor,
            Quantity_implemented, Quantity_shipped, Quantity_of_losses, Quantity_avaliable, Needed_new,
            Can_be_cancelled_sure, Can_be_cancelled_maybe,
            Suggestion, Order_import, Status_import,
            Project, Target_assembly, Supplied_component_number, Component_revision, Component_name,
            Quantity_in_target_assembly, Quantity_of_target_assemblies, Component_type,
            For_supplied_as_assembly_components_provided_by_supplier, Components_quantity_in_assembly,
            Part_material, Producer, Catalogue_number, Producer_article, Distributer, Distributer_article,
            MBOM_type, Mass_kg, Unit_of_measure, Height, Width, Length, Advanced_group, Address,
            Document_no, Zakaz_no, Date_needed, Date_expected, Cost_total_rub,
            Supplier, Price_of_single_unit, Location, Source, Initial_doc_no
        )
        SELECT
            p.ERP_ID, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 'import_do', 'import_do', rc.parent_id,
            p.type, p.where_from, p.where_to, p.Quantity_of_parts_total, -1 * rc.can_total,
            p.Quantity_in_transactions, p.inProcess_purchase, p.inProcess_manufacturing,
            p.Quantity_in_warehouse, p.Quantity_in_kitting, p.Quantity_on_shopfloor,
            p.Quantity_implemented, p.Quantity_shipped, p.Quantity_of_losses, p.Quantity_avaliable, p.Needed_new,
            p.Can_be_cancelled_sure, p.Can_be_cancelled_maybe,
            'Импортировать', 'Ожидание', 'Новая',
            p.Project, p.Target_assembly, p.Supplied_component_number, p.Component_revision, p.Component_name,
            p.Quantity_in_target_assembly, p.Quantity_of_target_assemblies, p.Component_type,
            p.For_supplied_as_assembly_components_provided_by_supplier, p.Components_quantity_in_assembly,
            p.Part_material, p.Producer, p.Catalogue_number, p.Producer_article, p.Distributer, p.Distributer_article,
            p.MBOM_type, p.Mass_kg, p.Unit_of_measure, p.Height, p.Width, p.Length, p.Advanced_group, p.Address,
            p.Document_no, p.Zakaz_no, p.Date_needed, p.Date_expected, p.Cost_total_rub,
            p.Supplier, p.Price_of_single_unit, p.Location, p.Source, p.Initial_doc_no
        FROM tmp_import_do_replace_change rc
        INNER JOIN `Import` p ON p.id = rc.parent_id;

        /* Вторая новая: qty = parent_qty + (sure + maybe), Suggestion='Отменить' */
        INSERT INTO `Import` (
            ERP_ID, created_at, updated_at, created_by, updated_by, linked_transaction,
            type, where_from, where_to, Quantity_of_parts_total, Quantity_change,
            Quantity_in_transactions, inProcess_purchase, inProcess_manufacturing,
            Quantity_in_warehouse, Quantity_in_kitting, Quantity_on_shopfloor,
            Quantity_implemented, Quantity_shipped, Quantity_of_losses, Quantity_avaliable, Needed_new,
            Can_be_cancelled_sure, Can_be_cancelled_maybe,
            Suggestion, Order_import, Status_import,
            Project, Target_assembly, Supplied_component_number, Component_revision, Component_name,
            Quantity_in_target_assembly, Quantity_of_target_assemblies, Component_type,
            For_supplied_as_assembly_components_provided_by_supplier, Components_quantity_in_assembly,
            Part_material, Producer, Catalogue_number, Producer_article, Distributer, Distributer_article,
            MBOM_type, Mass_kg, Unit_of_measure, Height, Width, Length, Advanced_group, Address,
            Document_no, Zakaz_no, Date_needed, Date_expected, Cost_total_rub,
            Supplier, Price_of_single_unit, Location, Source, Initial_doc_no
        )
        SELECT
            p.ERP_ID, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 'import_do', 'import_do', rc.parent_id,
            p.type, p.where_from, p.where_to, p.Quantity_of_parts_total, (rc.parent_qty + rc.can_total),
            p.Quantity_in_transactions, p.inProcess_purchase, p.inProcess_manufacturing,
            p.Quantity_in_warehouse, p.Quantity_in_kitting, p.Quantity_on_shopfloor,
            p.Quantity_implemented, p.Quantity_shipped, p.Quantity_of_losses, p.Quantity_avaliable, p.Needed_new,
            p.Can_be_cancelled_sure, p.Can_be_cancelled_maybe,
            'Отменить', 'Ожидание', 'Новая',
            p.Project, p.Target_assembly, p.Supplied_component_number, p.Component_revision, p.Component_name,
            p.Quantity_in_target_assembly, p.Quantity_of_target_assemblies, p.Component_type,
            p.For_supplied_as_assembly_components_provided_by_supplier, p.Components_quantity_in_assembly,
            p.Part_material, p.Producer, p.Catalogue_number, p.Producer_article, p.Distributer, p.Distributer_article,
            p.MBOM_type, p.Mass_kg, p.Unit_of_measure, p.Height, p.Width, p.Length, p.Advanced_group, p.Address,
            p.Document_no, p.Zakaz_no, p.Date_needed, p.Date_expected, p.Cost_total_rub,
            p.Supplier, p.Price_of_single_unit, p.Location, p.Source, p.Initial_doc_no
        FROM tmp_import_do_replace_change rc
        INNER JOIN `Import` p ON p.id = rc.parent_id;

        DROP TEMPORARY TABLE IF EXISTS tmp_import_do_replace_change;

        /* 4) Suggestion='Импортировать' AND Order_import='Выполнить':
              вставить в Transactions, затем Status_import='Импортировано' */
        DROP TEMPORARY TABLE IF EXISTS tmp_import_do_to_transactions;
        CREATE TEMPORARY TABLE tmp_import_do_to_transactions (
            id INT UNSIGNED NOT NULL PRIMARY KEY
        );

        INSERT INTO tmp_import_do_to_transactions (id)
        SELECT i.id
        FROM `Import` i
        INNER JOIN tmp_import_do_initial_ids s ON s.id = i.id
        WHERE i.Status_import = 'Новая'
          AND i.Suggestion = 'Импортировать'
          AND i.Order_import = 'Выполнить';

        INSERT INTO `Transactions` (
            ERP_ID, created_at, updated_at, created_by, updated_by, linked_transaction,
            type, where_from, where_to, Quantity_of_parts_total, Quantity_change, Status_transaction,
            Project, Target_assembly, Supplied_component_number, Component_revision, Component_name,
            Quantity_in_target_assembly, Quantity_of_target_assemblies, Components_quantity_in_assembly, Component_type,
            For_supplied_as_assembly_components_provided_by_supplier, Part_material, Producer, Catalogue_number,
            Producer_article, Distributer, Distributer_article, MBOM_type, Mass_kg, Unit_of_measure,
            Height, Width, Length, Advanced_group, Address, Document_no, Zakaz_no, Date_needed, Date_expected, Cost_total_rub
        )
        SELECT
            i.ERP_ID, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 'import_do', 'import_do', i.linked_transaction,
            i.type, i.where_from, i.where_to, COALESCE(i.Quantity_of_parts_total, 0), COALESCE(i.Quantity_change, 0), 'В ожидании',
            i.Project, i.Target_assembly, i.Supplied_component_number, i.Component_revision, i.Component_name,
            COALESCE(i.Quantity_in_target_assembly, 0), COALESCE(i.Quantity_of_target_assemblies, 0), COALESCE(i.Components_quantity_in_assembly, 0), i.Component_type,
            i.For_supplied_as_assembly_components_provided_by_supplier, i.Part_material, i.Producer, i.Catalogue_number,
            i.Producer_article, i.Distributer, i.Distributer_article, i.MBOM_type, i.Mass_kg, i.Unit_of_measure,
            i.Height, i.Width, i.Length, i.Advanced_group, i.Address, i.Document_no, i.Zakaz_no, i.Date_needed, i.Date_expected, i.Cost_total_rub
        FROM `Import` i
        INNER JOIN tmp_import_do_to_transactions x ON x.id = i.id;

        UPDATE `Import` i
        INNER JOIN tmp_import_do_to_transactions x ON x.id = i.id
        SET
            i.Status_import = 'Импортировано',
            i.updated_at = CURRENT_TIMESTAMP;

        DROP TEMPORARY TABLE IF EXISTS tmp_import_do_to_transactions;
        DROP TEMPORARY TABLE IF EXISTS tmp_import_do_initial_ids;

        COMMIT;
        DO RELEASE_LOCK('lock_process_import_do');
    END IF;
END$$

DELIMITER ;
