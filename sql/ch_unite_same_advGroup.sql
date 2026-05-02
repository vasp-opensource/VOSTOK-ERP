-- ch_unite_same_advGroup: объединение change-заявок по ERP_ID + Advanced_group.
-- В tmp_ch_ids попадают только id из групп, где подходящих строк >= 2 — иначе одиночные
-- строки не трогаем и не создаём «замену» при каждом запуске.
-- Блокировка: lock_ch_unite_same_advGroup
--
-- Отбор change: where_from = «внешний», where_to = «склад», Status_warehouse = «Новая», Status_transaction = «В ожидании».
-- Заменённые строки: Status_transaction = «Заменено», Status_warehouse = «Норма».
-- Новая объединённая строка: те же where_from/where_to, Status_warehouse = «Новая», Status_transaction = «В ожидании»; реквизиты change — MIN / SUM(Quantity_ordered), Order_purch и Order_wh в новой строке — NULL (как ранее). Main не затрагивается.

DELIMITER $$

DROP PROCEDURE IF EXISTS ch_unite_same_advGroup$$

CREATE PROCEDURE ch_unite_same_advGroup()
BEGIN
    DECLARE v_lock_ok INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        IF v_lock_ok = 1 THEN
            DO RELEASE_LOCK('lock_ch_unite_same_advGroup');
        END IF;
        RESIGNAL;
    END;

    SELECT GET_LOCK('lock_ch_unite_same_advGroup', 0) INTO v_lock_ok;


    IF COALESCE(v_lock_ok, 0) <> 1 THEN

        SET @erp_batch_blocked_message = 'Blocked: lock_ch_unite_same_advGroup lock is already held';

    END IF;

    IF v_lock_ok = 1 THEN
        START TRANSACTION;

        DROP TEMPORARY TABLE IF EXISTS tmp_ch_ids;
        CREATE TEMPORARY TABLE tmp_ch_ids (
            id INT UNSIGNED NOT NULL PRIMARY KEY
        );

        INSERT INTO tmp_ch_ids (id)
        SELECT t.id
        FROM `Transactions` t
        WHERE t.type = 'change'
          AND t.where_from = 'внешний'
          AND t.where_to = 'склад'
          AND t.Status_warehouse = 'Новая'
          AND t.Status_transaction = 'В ожидании'
          AND EXISTS (
              SELECT 1
              FROM `Transactions` t2
              WHERE t2.type = 'change'
                AND t2.where_from = 'внешний'
                AND t2.where_to = 'склад'
                AND t2.Status_warehouse = 'Новая'
                AND t2.Status_transaction = 'В ожидании'
                AND t2.ERP_ID = t.ERP_ID
                AND t2.Advanced_group <=> t.Advanced_group
                AND t2.id <> t.id
          );

        UPDATE `Transactions` t
        JOIN tmp_ch_ids x ON x.id = t.id
           SET t.Status_transaction = 'Заменено',
               t.Status_warehouse   = 'Норма',
               t.updated_by         = CASE
                                         WHEN t.updated_by IS NULL OR TRIM(COALESCE(t.updated_by, '')) = '' THEN 'ch_unite_same_advGroup'
                                         ELSE CONCAT(t.updated_by, '; ', 'ch_unite_same_advGroup')
                                      END,
               t.updated_at         = CURRENT_TIMESTAMP;

        /* INSERT: сумма и MIN по одному JOIN tmp_ch_ids (два подзапроса с тем же TEMP в одном операторе → MySQL #1137). */
        INSERT INTO `Transactions` (
            ERP_ID, created_at, updated_at, created_by, updated_by,
            type, where_from, where_to,
            Quantity_of_parts_total, Quantity_change, Status_transaction,
            Project, Target_assembly, Supplied_component_number, Component_revision, Component_name,
            Quantity_in_target_assembly, Quantity_of_target_assemblies, Components_quantity_in_assembly,
            Component_type, For_supplied_as_assembly_components_provided_by_supplier, Part_material,
            Producer, Catalogue_number, Producer_article, Distributer, Distributer_article,
            MBOM_type, Mass_kg, Unit_of_measure, Height, Width, Length,
            Advanced_group, Address,
            Recommend_purchprod,
            Order_purch, Order_wh, Order_prod, Order_OTK,
            Order_sv, Recommend_wh, Quantity_ordered, Replace_to, Rework_to, Rework_from,
            Status_warehouse,
            Document_no, Document_date, Zakaz_no, Date_needed, Date_expected, Cost_total_rub,
            Supplier, Location, Source, Initial_doc_no
        )
        SELECT
            agg.`ERP_ID`,
            CURRENT_TIMESTAMP,
            CURRENT_TIMESTAMP,
            'ch_unite_same_advGroup',
            'ch_unite_same_advGroup',
            'change',
            'внешний',
            'склад',
            0,
            agg.`sum_qty_change`,
            'В ожидании',
            agg.`Project`,
            agg.`Target_assembly`,
            agg.`Supplied_component_number`,
            agg.`Component_revision`,
            agg.`Component_name`,
            agg.`Quantity_in_target_assembly`,
            agg.`Quantity_of_target_assemblies`,
            agg.`Components_quantity_in_assembly`,
            agg.`Component_type`,
            agg.`For_supplied_as_assembly_components_provided_by_supplier`,
            agg.`Part_material`,
            agg.`Producer`,
            agg.`Catalogue_number`,
            agg.`Producer_article`,
            agg.`Distributer`,
            agg.`Distributer_article`,
            agg.`MBOM_type`,
            agg.`Mass_kg`,
            agg.`Unit_of_measure`,
            agg.`Height`,
            agg.`Width`,
            agg.`Length`,
            agg.`Advanced_group`,
            agg.`Address`,
            agg.`Recommend_purchprod`,
            NULL,
            NULL,
            agg.`Order_prod`,
            agg.`Order_OTK`,
            agg.`Order_sv`,
            agg.`Recommend_wh`,
            agg.`sum_qty_ord`,
            agg.`Replace_to`,
            agg.`Rework_to`,
            agg.`Rework_from`,
            'Новая',
            agg.`Document_no`,
            agg.`Document_date`,
            agg.`Zakaz_no`,
            agg.`Date_needed`,
            agg.`Date_expected`,
            agg.`Cost_total_rub`,
            agg.`Supplier`,
            agg.`Location`,
            agg.`Source`,
            agg.`Initial_doc_no`
        FROM (
            SELECT
                t.`ERP_ID`,
                t.`Advanced_group`,
                SUM(COALESCE(t.`Quantity_change`, 0)) AS `sum_qty_change`,
                MIN(t.`Project`) AS `Project`,
                MIN(t.`Target_assembly`) AS `Target_assembly`,
                MIN(t.`Supplied_component_number`) AS `Supplied_component_number`,
                MIN(t.`Component_revision`) AS `Component_revision`,
                MIN(t.`Component_name`) AS `Component_name`,
                MIN(t.`Quantity_in_target_assembly`) AS `Quantity_in_target_assembly`,
                MIN(t.`Quantity_of_target_assemblies`) AS `Quantity_of_target_assemblies`,
                MIN(t.`Components_quantity_in_assembly`) AS `Components_quantity_in_assembly`,
                MIN(t.`Component_type`) AS `Component_type`,
                MIN(t.`For_supplied_as_assembly_components_provided_by_supplier`) AS `For_supplied_as_assembly_components_provided_by_supplier`,
                MIN(t.`Part_material`) AS `Part_material`,
                MIN(t.`Producer`) AS `Producer`,
                MIN(t.`Catalogue_number`) AS `Catalogue_number`,
                MIN(t.`Producer_article`) AS `Producer_article`,
                MIN(t.`Distributer`) AS `Distributer`,
                MIN(t.`Distributer_article`) AS `Distributer_article`,
                MIN(t.`MBOM_type`) AS `MBOM_type`,
                MIN(t.`Mass_kg`) AS `Mass_kg`,
                MIN(t.`Unit_of_measure`) AS `Unit_of_measure`,
                MIN(t.`Height`) AS `Height`,
                MIN(t.`Width`) AS `Width`,
                MIN(t.`Length`) AS `Length`,
                MIN(t.`Address`) AS `Address`,
                MIN(t.`Recommend_purchprod`) AS `Recommend_purchprod`,
                MIN(t.`Document_no`) AS `Document_no`,
                MIN(t.`Document_date`) AS `Document_date`,
                MIN(t.`Zakaz_no`) AS `Zakaz_no`,
                MIN(t.`Date_needed`) AS `Date_needed`,
                MIN(t.`Date_expected`) AS `Date_expected`,
                MIN(t.`Cost_total_rub`) AS `Cost_total_rub`,
                MIN(t.`Supplier`) AS `Supplier`,
                MIN(t.`Location`) AS `Location`,
                MIN(t.`Source`) AS `Source`,
                MIN(t.`Initial_doc_no`) AS `Initial_doc_no`,
                MIN(t.`Order_prod`) AS `Order_prod`,
                MIN(t.`Order_OTK`) AS `Order_OTK`,
                MIN(t.`Order_sv`) AS `Order_sv`,
                MIN(t.`Recommend_wh`) AS `Recommend_wh`,
                SUM(COALESCE(t.`Quantity_ordered`, 0)) AS `sum_qty_ord`,
                MIN(t.`Replace_to`) AS `Replace_to`,
                MIN(t.`Rework_to`) AS `Rework_to`,
                MIN(t.`Rework_from`) AS `Rework_from`
            FROM `Transactions` t
            INNER JOIN tmp_ch_ids x ON x.`id` = t.`id`
            GROUP BY t.`ERP_ID`, t.`Advanced_group`
        ) agg
        WHERE agg.`sum_qty_change` > 0;

        DROP TEMPORARY TABLE IF EXISTS tmp_ch_ids;

        COMMIT;
        DO RELEASE_LOCK('lock_ch_unite_same_advGroup');
    END IF;
END$$

DELIMITER ;
