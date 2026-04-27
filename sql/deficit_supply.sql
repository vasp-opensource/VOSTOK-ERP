-- deficit_supply: обработка move со статусом склада "Дефицит поставки"
-- Новые реквизиты Transactions (Recommend_purchprod, Order_sv, Document_date, …) копируются из исходной строки
--   во все вставляемые move/change, как в ch_merge / deficit_wh.
-- Вход:
--   type='move', where_from='склад', where_to in ('брак','отгрузка','изделие'),
--   Status_transaction='В ожидании', Status_warehouse='Дефицит поставки'
--
-- Логика:
--   1) Обработка по группам Project + Advanced_group.
--   2) Внутри группы: пока есть "Дефицит поставки", берем 1 строку в приоритете
--      where_to: брак -> отгрузка -> изделие.
--   3) Для строки рассчитываем доступности:
--      - изготовление: (ожидание изготовления - потребность изготовления)
--      - закупка:      (ожидание закупок - потребность закупок)
--      - поставка:     (ожидание поставок - потребность поставок)
--   4) Строка всегда заменяется:
--      - либо целиком в статус ожидания;
--      - либо делится на "покрытую" часть + новый "Дефицит поставки" остаток;
--      - если покрыть нечем: создаем move "Ожидание поставки" и change "Новая".

DROP PROCEDURE IF EXISTS deficit_supply;

DELIMITER $$

CREATE PROCEDURE deficit_supply()
BEGIN
    DECLARE v_lock_ok INT DEFAULT 0;
    DECLARE v_group_left BIGINT DEFAULT 0;
    DECLARE v_rows_in_group BIGINT DEFAULT 0;

    DECLARE v_project TEXT;
    DECLARE v_adv_group TEXT;

    DECLARE v_tx_id INT;
    DECLARE v_erp_id VARCHAR(255);
    DECLARE v_req_qty BIGINT DEFAULT 0;
    DECLARE v_where_to VARCHAR(32);

    DECLARE v_expect_supply BIGINT DEFAULT 0;
    DECLARE v_need_supply BIGINT DEFAULT 0;
    DECLARE v_expect_purch BIGINT DEFAULT 0;
    DECLARE v_need_purch BIGINT DEFAULT 0;
    DECLARE v_expect_prod BIGINT DEFAULT 0;
    DECLARE v_need_prod BIGINT DEFAULT 0;

    DECLARE v_avail_supply BIGINT DEFAULT 0;
    DECLARE v_avail_purch BIGINT DEFAULT 0;
    DECLARE v_avail_prod BIGINT DEFAULT 0;

    DECLARE v_cover_qty BIGINT DEFAULT 0;
    DECLARE v_remain_qty BIGINT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        IF v_lock_ok = 1 THEN
            DO RELEASE_LOCK('lock_process_move_deficit_supply');
        END IF;
        RESIGNAL;
    END;

    SELECT GET_LOCK('lock_process_move_deficit_supply', 0) INTO v_lock_ok;

    IF v_lock_ok = 1 THEN
        START TRANSACTION;

        DROP TEMPORARY TABLE IF EXISTS tmp_deficit_supply_groups;
        CREATE TEMPORARY TABLE tmp_deficit_supply_groups (
            id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
            project TEXT NULL,
            adv_group TEXT NULL
        );

        INSERT INTO tmp_deficit_supply_groups (project, adv_group)
        SELECT DISTINCT t.Project, t.Advanced_group
        FROM `Transactions` t
        WHERE t.type = 'move'
          AND t.where_from = 'склад'
          AND t.where_to IN ('брак', 'отгрузка', 'изделие')
          AND t.Status_transaction = 'В ожидании'
          AND t.Status_warehouse = 'Дефицит поставки';

        group_loop: LOOP
            SELECT COUNT(*) INTO v_group_left FROM tmp_deficit_supply_groups;
            IF v_group_left = 0 THEN
                LEAVE group_loop;
            END IF;

            SELECT g.project, g.adv_group
              INTO v_project, v_adv_group
            FROM tmp_deficit_supply_groups g
            ORDER BY g.id
            LIMIT 1;

            row_loop: LOOP
                SELECT COUNT(*) INTO v_rows_in_group
                FROM `Transactions` t
                WHERE t.type = 'move'
                  AND t.where_from = 'склад'
                  AND t.where_to IN ('брак', 'отгрузка', 'изделие')
                  AND t.Status_transaction = 'В ожидании'
                  AND t.Status_warehouse = 'Дефицит поставки'
                  AND (t.Project <=> v_project)
                  AND (t.Advanced_group <=> v_adv_group);

                IF v_rows_in_group = 0 THEN
                    LEAVE row_loop;
                END IF;

                SELECT
                    t.id,
                    t.ERP_ID,
                    COALESCE(t.Quantity_of_parts_total, 0),
                    t.where_to
                INTO
                    v_tx_id,
                    v_erp_id,
                    v_req_qty,
                    v_where_to
                FROM `Transactions` t
                WHERE t.type = 'move'
                  AND t.where_from = 'склад'
                  AND t.where_to IN ('брак', 'отгрузка', 'изделие')
                  AND t.Status_transaction = 'В ожидании'
                  AND t.Status_warehouse = 'Дефицит поставки'
                  AND (t.Project <=> v_project)
                  AND (t.Advanced_group <=> v_adv_group)
                ORDER BY
                    CASE t.where_to
                        WHEN 'брак' THEN 1
                        WHEN 'отгрузка' THEN 2
                        WHEN 'изделие' THEN 3
                        ELSE 4
                    END,
                    t.id
                LIMIT 1;

                SET v_req_qty = GREATEST(COALESCE(v_req_qty, 0), 0);

                SELECT COALESCE(SUM(COALESCE(t.Quantity_change, 0)), 0)
                  INTO v_expect_supply
                FROM `Transactions` t
                WHERE t.ERP_ID = v_erp_id
                  AND (t.Project <=> v_project)
                  AND (t.Advanced_group <=> v_adv_group)
                  AND t.type = 'change'
                  AND t.where_from = 'внешний'
                  AND t.where_to = 'склад'
                  AND t.Status_transaction = 'В ожидании'
                  AND t.Status_warehouse = 'Новая';

                SELECT COALESCE(SUM(COALESCE(t.Quantity_of_parts_total, 0)), 0)
                  INTO v_need_supply
                FROM `Transactions` t
                WHERE t.ERP_ID = v_erp_id
                  AND (t.Project <=> v_project)
                  AND (t.Advanced_group <=> v_adv_group)
                  AND t.type = 'move'
                  AND t.where_from = 'склад'
                  AND t.where_to IN ('брак', 'отгрузка', 'изделие')
                  AND t.Status_transaction = 'В ожидании'
                  AND t.Status_warehouse IN ('Новая', 'Ожидание поставки');

                SELECT COALESCE(SUM(COALESCE(t.Quantity_change, 0)), 0)
                  INTO v_expect_purch
                FROM `Transactions` t
                WHERE t.ERP_ID = v_erp_id
                  AND (t.Project <=> v_project)
                  AND (t.Advanced_group <=> v_adv_group)
                  AND t.type = 'change'
                  AND t.where_from = 'внешний'
                  AND t.where_to = 'склад'
                  AND t.Status_transaction = 'В ожидании'
                  AND t.Status_warehouse = 'В закупке';

                SELECT COALESCE(SUM(COALESCE(t.Quantity_of_parts_total, 0)), 0)
                  INTO v_need_purch
                FROM `Transactions` t
                WHERE t.ERP_ID = v_erp_id
                  AND (t.Project <=> v_project)
                  AND (t.Advanced_group <=> v_adv_group)
                  AND t.type = 'move'
                  AND t.Status_transaction = 'В ожидании'
                  AND t.Status_warehouse = 'Ожидание закупки';

                SELECT COALESCE(SUM(COALESCE(t.Quantity_change, 0)), 0)
                  INTO v_expect_prod
                FROM `Transactions` t
                WHERE t.ERP_ID = v_erp_id
                  AND (t.Project <=> v_project)
                  AND (t.Advanced_group <=> v_adv_group)
                  AND t.type = 'change'
                  AND t.where_from = 'внешний'
                  AND t.where_to = 'склад'
                  AND t.Status_transaction = 'В ожидании'
                  AND t.Status_warehouse = 'В изготовлении';

                SELECT COALESCE(SUM(COALESCE(t.Quantity_of_parts_total, 0)), 0)
                  INTO v_need_prod
                FROM `Transactions` t
                WHERE t.ERP_ID = v_erp_id
                  AND (t.Project <=> v_project)
                  AND (t.Advanced_group <=> v_adv_group)
                  AND t.type = 'move'
                  AND t.Status_transaction = 'В ожидании'
                  AND t.Status_warehouse = 'Ожидание изготовления';

                SET v_avail_prod = GREATEST(v_expect_prod - v_need_prod, 0);
                SET v_avail_purch = GREATEST(v_expect_purch - v_need_purch, 0);
                SET v_avail_supply = GREATEST(v_expect_supply - v_need_supply, 0);

                UPDATE `Transactions`
                   SET Status_transaction = 'Заменено',
                       linked_transaction = v_tx_id,
                       Status_warehouse   = 'Норма',
                      updated_by         = CASE
                                               WHEN `updated_by` IS NULL OR TRIM(COALESCE(`updated_by`, '')) = '' THEN 'deficit_supply'
                                               ELSE CONCAT(`updated_by`, '; ', 'deficit_supply')
                                           END,
                       updated_at         = CURRENT_TIMESTAMP
                 WHERE id = v_tx_id;

                IF v_req_qty <= v_avail_prod THEN
                    INSERT INTO `Transactions` (
                        ERP_ID, created_at, updated_at, created_by, updated_by, linked_transaction,
                        type, where_from, where_to, Quantity_of_parts_total, Quantity_change, Status_transaction,
                        Project, Target_assembly, Supplied_component_number, Component_revision, Component_name,
                        Quantity_in_target_assembly, Quantity_of_target_assemblies, Components_quantity_in_assembly, Component_type,
                        For_supplied_as_assembly_components_provided_by_supplier, Part_material, Producer, Catalogue_number,
                        Producer_article, Distributer, Distributer_article, MBOM_type, Mass_kg, Unit_of_measure,
                        Height, Width, Length, Advanced_group, Address,
                        Recommend_purchprod,
                        Order_purch, Order_wh, Order_prod, Order_OTK,
                        Order_sv, Recommend_wh, Quantity_ordered, Replace_to, Rework_to, Rework_from,
                        Status_warehouse,
                        Document_no, Document_date, Zakaz_no, Date_needed, Date_expected, Cost_total_rub,
                        Supplier, Location, Source, Initial_doc_no
                    )
                    SELECT
                        t.ERP_ID, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 'deficit_supply', 'deficit_supply', v_tx_id,
                        'move', t.where_from, t.where_to, v_req_qty, 0, 'В ожидании',
                        t.Project, t.Target_assembly, t.Supplied_component_number, t.Component_revision, t.Component_name,
                        t.Quantity_in_target_assembly, t.Quantity_of_target_assemblies, t.Components_quantity_in_assembly, t.Component_type,
                        t.For_supplied_as_assembly_components_provided_by_supplier, t.Part_material, t.Producer, t.Catalogue_number,
                        t.Producer_article, t.Distributer, t.Distributer_article, t.MBOM_type, t.Mass_kg, t.Unit_of_measure,
                        t.Height, t.Width, t.Length, t.Advanced_group, t.Address,
                        t.Recommend_purchprod,
                        t.Order_purch, t.Order_wh, t.Order_prod, t.Order_OTK,
                        t.Order_sv, t.Recommend_wh, t.Quantity_ordered, t.Replace_to, t.Rework_to, t.Rework_from,
                        'Ожидание изготовления', t.Document_no, t.Document_date, t.Zakaz_no, t.Date_needed, t.Date_expected, t.Cost_total_rub,
                        t.Supplier, t.Location, t.Source, t.Initial_doc_no
                    FROM `Transactions` t
                    WHERE t.id = v_tx_id;

                ELSEIF v_avail_prod > 0 THEN
                    SET v_cover_qty = v_avail_prod;
                    SET v_remain_qty = v_req_qty - v_cover_qty;

                    INSERT INTO `Transactions` (
                        ERP_ID, created_at, updated_at, created_by, updated_by, linked_transaction,
                        type, where_from, where_to, Quantity_of_parts_total, Quantity_change, Status_transaction,
                        Project, Target_assembly, Supplied_component_number, Component_revision, Component_name,
                        Quantity_in_target_assembly, Quantity_of_target_assemblies, Components_quantity_in_assembly, Component_type,
                        For_supplied_as_assembly_components_provided_by_supplier, Part_material, Producer, Catalogue_number,
                        Producer_article, Distributer, Distributer_article, MBOM_type, Mass_kg, Unit_of_measure,
                        Height, Width, Length, Advanced_group, Address,
                        Recommend_purchprod,
                        Order_purch, Order_wh, Order_prod, Order_OTK,
                        Order_sv, Recommend_wh, Quantity_ordered, Replace_to, Rework_to, Rework_from,
                        Status_warehouse,
                        Document_no, Document_date, Zakaz_no, Date_needed, Date_expected, Cost_total_rub,
                        Supplier, Location, Source, Initial_doc_no
                    )
                    SELECT
                        t.ERP_ID, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 'deficit_supply', 'deficit_supply', v_tx_id,
                        'move', t.where_from, t.where_to, v_cover_qty, 0, 'В ожидании',
                        t.Project, t.Target_assembly, t.Supplied_component_number, t.Component_revision, t.Component_name,
                        t.Quantity_in_target_assembly, t.Quantity_of_target_assemblies, t.Components_quantity_in_assembly, t.Component_type,
                        t.For_supplied_as_assembly_components_provided_by_supplier, t.Part_material, t.Producer, t.Catalogue_number,
                        t.Producer_article, t.Distributer, t.Distributer_article, t.MBOM_type, t.Mass_kg, t.Unit_of_measure,
                        t.Height, t.Width, t.Length, t.Advanced_group, t.Address,
                        t.Recommend_purchprod,
                        t.Order_purch, t.Order_wh, t.Order_prod, t.Order_OTK,
                        t.Order_sv, t.Recommend_wh, t.Quantity_ordered, t.Replace_to, t.Rework_to, t.Rework_from,
                        'Ожидание изготовления', t.Document_no, t.Document_date, t.Zakaz_no, t.Date_needed, t.Date_expected, t.Cost_total_rub,
                        t.Supplier, t.Location, t.Source, t.Initial_doc_no
                    FROM `Transactions` t
                    WHERE t.id = v_tx_id;

                    INSERT INTO `Transactions` (
                        ERP_ID, created_at, updated_at, created_by, updated_by, linked_transaction,
                        type, where_from, where_to, Quantity_of_parts_total, Quantity_change, Status_transaction,
                        Project, Target_assembly, Supplied_component_number, Component_revision, Component_name,
                        Quantity_in_target_assembly, Quantity_of_target_assemblies, Components_quantity_in_assembly, Component_type,
                        For_supplied_as_assembly_components_provided_by_supplier, Part_material, Producer, Catalogue_number,
                        Producer_article, Distributer, Distributer_article, MBOM_type, Mass_kg, Unit_of_measure,
                        Height, Width, Length, Advanced_group, Address,
                        Recommend_purchprod,
                        Order_purch, Order_wh, Order_prod, Order_OTK,
                        Order_sv, Recommend_wh, Quantity_ordered, Replace_to, Rework_to, Rework_from,
                        Status_warehouse,
                        Document_no, Document_date, Zakaz_no, Date_needed, Date_expected, Cost_total_rub,
                        Supplier, Location, Source, Initial_doc_no
                    )
                    SELECT
                        t.ERP_ID, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 'deficit_supply', 'deficit_supply', v_tx_id,
                        'move', t.where_from, t.where_to, v_remain_qty, 0, 'В ожидании',
                        t.Project, t.Target_assembly, t.Supplied_component_number, t.Component_revision, t.Component_name,
                        t.Quantity_in_target_assembly, t.Quantity_of_target_assemblies, t.Components_quantity_in_assembly, t.Component_type,
                        t.For_supplied_as_assembly_components_provided_by_supplier, t.Part_material, t.Producer, t.Catalogue_number,
                        t.Producer_article, t.Distributer, t.Distributer_article, t.MBOM_type, t.Mass_kg, t.Unit_of_measure,
                        t.Height, t.Width, t.Length, t.Advanced_group, t.Address,
                        t.Recommend_purchprod,
                        t.Order_purch, t.Order_wh, t.Order_prod, t.Order_OTK,
                        t.Order_sv, t.Recommend_wh, t.Quantity_ordered, t.Replace_to, t.Rework_to, t.Rework_from,
                        'Дефицит поставки', t.Document_no, t.Document_date, t.Zakaz_no, t.Date_needed, t.Date_expected, t.Cost_total_rub,
                        t.Supplier, t.Location, t.Source, t.Initial_doc_no
                    FROM `Transactions` t
                    WHERE t.id = v_tx_id;

                ELSEIF v_req_qty <= v_avail_purch THEN
                    INSERT INTO `Transactions` (
                        ERP_ID, created_at, updated_at, created_by, updated_by, linked_transaction,
                        type, where_from, where_to, Quantity_of_parts_total, Quantity_change, Status_transaction,
                        Project, Target_assembly, Supplied_component_number, Component_revision, Component_name,
                        Quantity_in_target_assembly, Quantity_of_target_assemblies, Components_quantity_in_assembly, Component_type,
                        For_supplied_as_assembly_components_provided_by_supplier, Part_material, Producer, Catalogue_number,
                        Producer_article, Distributer, Distributer_article, MBOM_type, Mass_kg, Unit_of_measure,
                        Height, Width, Length, Advanced_group, Address,
                        Recommend_purchprod,
                        Order_purch, Order_wh, Order_prod, Order_OTK,
                        Order_sv, Recommend_wh, Quantity_ordered, Replace_to, Rework_to, Rework_from,
                        Status_warehouse,
                        Document_no, Document_date, Zakaz_no, Date_needed, Date_expected, Cost_total_rub,
                        Supplier, Location, Source, Initial_doc_no
                    )
                    SELECT
                        t.ERP_ID, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 'deficit_supply', 'deficit_supply', v_tx_id,
                        'move', t.where_from, t.where_to, v_req_qty, 0, 'В ожидании',
                        t.Project, t.Target_assembly, t.Supplied_component_number, t.Component_revision, t.Component_name,
                        t.Quantity_in_target_assembly, t.Quantity_of_target_assemblies, t.Components_quantity_in_assembly, t.Component_type,
                        t.For_supplied_as_assembly_components_provided_by_supplier, t.Part_material, t.Producer, t.Catalogue_number,
                        t.Producer_article, t.Distributer, t.Distributer_article, t.MBOM_type, t.Mass_kg, t.Unit_of_measure,
                        t.Height, t.Width, t.Length, t.Advanced_group, t.Address,
                        t.Recommend_purchprod,
                        t.Order_purch, t.Order_wh, t.Order_prod, t.Order_OTK,
                        t.Order_sv, t.Recommend_wh, t.Quantity_ordered, t.Replace_to, t.Rework_to, t.Rework_from,
                        'Ожидание закупки', t.Document_no, t.Document_date, t.Zakaz_no, t.Date_needed, t.Date_expected, t.Cost_total_rub,
                        t.Supplier, t.Location, t.Source, t.Initial_doc_no
                    FROM `Transactions` t
                    WHERE t.id = v_tx_id;

                ELSEIF v_avail_purch > 0 THEN
                    SET v_cover_qty = v_avail_purch;
                    SET v_remain_qty = v_req_qty - v_cover_qty;

                    INSERT INTO `Transactions` (
                        ERP_ID, created_at, updated_at, created_by, updated_by, linked_transaction,
                        type, where_from, where_to, Quantity_of_parts_total, Quantity_change, Status_transaction,
                        Project, Target_assembly, Supplied_component_number, Component_revision, Component_name,
                        Quantity_in_target_assembly, Quantity_of_target_assemblies, Components_quantity_in_assembly, Component_type,
                        For_supplied_as_assembly_components_provided_by_supplier, Part_material, Producer, Catalogue_number,
                        Producer_article, Distributer, Distributer_article, MBOM_type, Mass_kg, Unit_of_measure,
                        Height, Width, Length, Advanced_group, Address,
                        Recommend_purchprod,
                        Order_purch, Order_wh, Order_prod, Order_OTK,
                        Order_sv, Recommend_wh, Quantity_ordered, Replace_to, Rework_to, Rework_from,
                        Status_warehouse,
                        Document_no, Document_date, Zakaz_no, Date_needed, Date_expected, Cost_total_rub,
                        Supplier, Location, Source, Initial_doc_no
                    )
                    SELECT
                        t.ERP_ID, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 'deficit_supply', 'deficit_supply', v_tx_id,
                        'move', t.where_from, t.where_to, v_cover_qty, 0, 'В ожидании',
                        t.Project, t.Target_assembly, t.Supplied_component_number, t.Component_revision, t.Component_name,
                        t.Quantity_in_target_assembly, t.Quantity_of_target_assemblies, t.Components_quantity_in_assembly, t.Component_type,
                        t.For_supplied_as_assembly_components_provided_by_supplier, t.Part_material, t.Producer, t.Catalogue_number,
                        t.Producer_article, t.Distributer, t.Distributer_article, t.MBOM_type, t.Mass_kg, t.Unit_of_measure,
                        t.Height, t.Width, t.Length, t.Advanced_group, t.Address,
                        t.Recommend_purchprod,
                        t.Order_purch, t.Order_wh, t.Order_prod, t.Order_OTK,
                        t.Order_sv, t.Recommend_wh, t.Quantity_ordered, t.Replace_to, t.Rework_to, t.Rework_from,
                        'Ожидание закупки', t.Document_no, t.Document_date, t.Zakaz_no, t.Date_needed, t.Date_expected, t.Cost_total_rub,
                        t.Supplier, t.Location, t.Source, t.Initial_doc_no
                    FROM `Transactions` t
                    WHERE t.id = v_tx_id;

                    INSERT INTO `Transactions` (
                        ERP_ID, created_at, updated_at, created_by, updated_by, linked_transaction,
                        type, where_from, where_to, Quantity_of_parts_total, Quantity_change, Status_transaction,
                        Project, Target_assembly, Supplied_component_number, Component_revision, Component_name,
                        Quantity_in_target_assembly, Quantity_of_target_assemblies, Components_quantity_in_assembly, Component_type,
                        For_supplied_as_assembly_components_provided_by_supplier, Part_material, Producer, Catalogue_number,
                        Producer_article, Distributer, Distributer_article, MBOM_type, Mass_kg, Unit_of_measure,
                        Height, Width, Length, Advanced_group, Address,
                        Recommend_purchprod,
                        Order_purch, Order_wh, Order_prod, Order_OTK,
                        Order_sv, Recommend_wh, Quantity_ordered, Replace_to, Rework_to, Rework_from,
                        Status_warehouse,
                        Document_no, Document_date, Zakaz_no, Date_needed, Date_expected, Cost_total_rub,
                        Supplier, Location, Source, Initial_doc_no
                    )
                    SELECT
                        t.ERP_ID, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 'deficit_supply', 'deficit_supply', v_tx_id,
                        'move', t.where_from, t.where_to, v_remain_qty, 0, 'В ожидании',
                        t.Project, t.Target_assembly, t.Supplied_component_number, t.Component_revision, t.Component_name,
                        t.Quantity_in_target_assembly, t.Quantity_of_target_assemblies, t.Components_quantity_in_assembly, t.Component_type,
                        t.For_supplied_as_assembly_components_provided_by_supplier, t.Part_material, t.Producer, t.Catalogue_number,
                        t.Producer_article, t.Distributer, t.Distributer_article, t.MBOM_type, t.Mass_kg, t.Unit_of_measure,
                        t.Height, t.Width, t.Length, t.Advanced_group, t.Address,
                        t.Recommend_purchprod,
                        t.Order_purch, t.Order_wh, t.Order_prod, t.Order_OTK,
                        t.Order_sv, t.Recommend_wh, t.Quantity_ordered, t.Replace_to, t.Rework_to, t.Rework_from,
                        'Дефицит поставки', t.Document_no, t.Document_date, t.Zakaz_no, t.Date_needed, t.Date_expected, t.Cost_total_rub,
                        t.Supplier, t.Location, t.Source, t.Initial_doc_no
                    FROM `Transactions` t
                    WHERE t.id = v_tx_id;

                ELSEIF v_req_qty <= v_avail_supply THEN
                    INSERT INTO `Transactions` (
                        ERP_ID, created_at, updated_at, created_by, updated_by, linked_transaction,
                        type, where_from, where_to, Quantity_of_parts_total, Quantity_change, Status_transaction,
                        Project, Target_assembly, Supplied_component_number, Component_revision, Component_name,
                        Quantity_in_target_assembly, Quantity_of_target_assemblies, Components_quantity_in_assembly, Component_type,
                        For_supplied_as_assembly_components_provided_by_supplier, Part_material, Producer, Catalogue_number,
                        Producer_article, Distributer, Distributer_article, MBOM_type, Mass_kg, Unit_of_measure,
                        Height, Width, Length, Advanced_group, Address,
                        Recommend_purchprod,
                        Order_purch, Order_wh, Order_prod, Order_OTK,
                        Order_sv, Recommend_wh, Quantity_ordered, Replace_to, Rework_to, Rework_from,
                        Status_warehouse,
                        Document_no, Document_date, Zakaz_no, Date_needed, Date_expected, Cost_total_rub,
                        Supplier, Location, Source, Initial_doc_no
                    )
                    SELECT
                        t.ERP_ID, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 'deficit_supply', 'deficit_supply', v_tx_id,
                        'move', t.where_from, t.where_to, v_req_qty, 0, 'В ожидании',
                        t.Project, t.Target_assembly, t.Supplied_component_number, t.Component_revision, t.Component_name,
                        t.Quantity_in_target_assembly, t.Quantity_of_target_assemblies, t.Components_quantity_in_assembly, t.Component_type,
                        t.For_supplied_as_assembly_components_provided_by_supplier, t.Part_material, t.Producer, t.Catalogue_number,
                        t.Producer_article, t.Distributer, t.Distributer_article, t.MBOM_type, t.Mass_kg, t.Unit_of_measure,
                        t.Height, t.Width, t.Length, t.Advanced_group, t.Address,
                        t.Recommend_purchprod,
                        t.Order_purch, t.Order_wh, t.Order_prod, t.Order_OTK,
                        t.Order_sv, t.Recommend_wh, t.Quantity_ordered, t.Replace_to, t.Rework_to, t.Rework_from,
                        'Ожидание поставки', t.Document_no, t.Document_date, t.Zakaz_no, t.Date_needed, t.Date_expected, t.Cost_total_rub,
                        t.Supplier, t.Location, t.Source, t.Initial_doc_no
                    FROM `Transactions` t
                    WHERE t.id = v_tx_id;

                ELSEIF v_avail_supply > 0 THEN
                    SET v_cover_qty = v_avail_supply;
                    SET v_remain_qty = v_req_qty - v_cover_qty;

                    INSERT INTO `Transactions` (
                        ERP_ID, created_at, updated_at, created_by, updated_by, linked_transaction,
                        type, where_from, where_to, Quantity_of_parts_total, Quantity_change, Status_transaction,
                        Project, Target_assembly, Supplied_component_number, Component_revision, Component_name,
                        Quantity_in_target_assembly, Quantity_of_target_assemblies, Components_quantity_in_assembly, Component_type,
                        For_supplied_as_assembly_components_provided_by_supplier, Part_material, Producer, Catalogue_number,
                        Producer_article, Distributer, Distributer_article, MBOM_type, Mass_kg, Unit_of_measure,
                        Height, Width, Length, Advanced_group, Address,
                        Recommend_purchprod,
                        Order_purch, Order_wh, Order_prod, Order_OTK,
                        Order_sv, Recommend_wh, Quantity_ordered, Replace_to, Rework_to, Rework_from,
                        Status_warehouse,
                        Document_no, Document_date, Zakaz_no, Date_needed, Date_expected, Cost_total_rub,
                        Supplier, Location, Source, Initial_doc_no
                    )
                    SELECT
                        t.ERP_ID, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 'deficit_supply', 'deficit_supply', v_tx_id,
                        'move', t.where_from, t.where_to, v_cover_qty, 0, 'В ожидании',
                        t.Project, t.Target_assembly, t.Supplied_component_number, t.Component_revision, t.Component_name,
                        t.Quantity_in_target_assembly, t.Quantity_of_target_assemblies, t.Components_quantity_in_assembly, t.Component_type,
                        t.For_supplied_as_assembly_components_provided_by_supplier, t.Part_material, t.Producer, t.Catalogue_number,
                        t.Producer_article, t.Distributer, t.Distributer_article, t.MBOM_type, t.Mass_kg, t.Unit_of_measure,
                        t.Height, t.Width, t.Length, t.Advanced_group, t.Address,
                        t.Recommend_purchprod,
                        t.Order_purch, t.Order_wh, t.Order_prod, t.Order_OTK,
                        t.Order_sv, t.Recommend_wh, t.Quantity_ordered, t.Replace_to, t.Rework_to, t.Rework_from,
                        'Ожидание поставки', t.Document_no, t.Document_date, t.Zakaz_no, t.Date_needed, t.Date_expected, t.Cost_total_rub,
                        t.Supplier, t.Location, t.Source, t.Initial_doc_no
                    FROM `Transactions` t
                    WHERE t.id = v_tx_id;

                    INSERT INTO `Transactions` (
                        ERP_ID, created_at, updated_at, created_by, updated_by, linked_transaction,
                        type, where_from, where_to, Quantity_of_parts_total, Quantity_change, Status_transaction,
                        Project, Target_assembly, Supplied_component_number, Component_revision, Component_name,
                        Quantity_in_target_assembly, Quantity_of_target_assemblies, Components_quantity_in_assembly, Component_type,
                        For_supplied_as_assembly_components_provided_by_supplier, Part_material, Producer, Catalogue_number,
                        Producer_article, Distributer, Distributer_article, MBOM_type, Mass_kg, Unit_of_measure,
                        Height, Width, Length, Advanced_group, Address,
                        Recommend_purchprod,
                        Order_purch, Order_wh, Order_prod, Order_OTK,
                        Order_sv, Recommend_wh, Quantity_ordered, Replace_to, Rework_to, Rework_from,
                        Status_warehouse,
                        Document_no, Document_date, Zakaz_no, Date_needed, Date_expected, Cost_total_rub,
                        Supplier, Location, Source, Initial_doc_no
                    )
                    SELECT
                        t.ERP_ID, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 'deficit_supply', 'deficit_supply', v_tx_id,
                        'move', t.where_from, t.where_to, v_remain_qty, 0, 'В ожидании',
                        t.Project, t.Target_assembly, t.Supplied_component_number, t.Component_revision, t.Component_name,
                        t.Quantity_in_target_assembly, t.Quantity_of_target_assemblies, t.Components_quantity_in_assembly, t.Component_type,
                        t.For_supplied_as_assembly_components_provided_by_supplier, t.Part_material, t.Producer, t.Catalogue_number,
                        t.Producer_article, t.Distributer, t.Distributer_article, t.MBOM_type, t.Mass_kg, t.Unit_of_measure,
                        t.Height, t.Width, t.Length, t.Advanced_group, t.Address,
                        t.Recommend_purchprod,
                        t.Order_purch, t.Order_wh, t.Order_prod, t.Order_OTK,
                        t.Order_sv, t.Recommend_wh, t.Quantity_ordered, t.Replace_to, t.Rework_to, t.Rework_from,
                        'Дефицит поставки', t.Document_no, t.Document_date, t.Zakaz_no, t.Date_needed, t.Date_expected, t.Cost_total_rub,
                        t.Supplier, t.Location, t.Source, t.Initial_doc_no
                    FROM `Transactions` t
                    WHERE t.id = v_tx_id;

                ELSE
                    INSERT INTO `Transactions` (
                        ERP_ID, created_at, updated_at, created_by, updated_by, linked_transaction,
                        type, where_from, where_to, Quantity_of_parts_total, Quantity_change, Status_transaction,
                        Project, Target_assembly, Supplied_component_number, Component_revision, Component_name,
                        Quantity_in_target_assembly, Quantity_of_target_assemblies, Components_quantity_in_assembly, Component_type,
                        For_supplied_as_assembly_components_provided_by_supplier, Part_material, Producer, Catalogue_number,
                        Producer_article, Distributer, Distributer_article, MBOM_type, Mass_kg, Unit_of_measure,
                        Height, Width, Length, Advanced_group, Address,
                        Recommend_purchprod,
                        Order_purch, Order_wh, Order_prod, Order_OTK,
                        Order_sv, Recommend_wh, Quantity_ordered, Replace_to, Rework_to, Rework_from,
                        Status_warehouse,
                        Document_no, Document_date, Zakaz_no, Date_needed, Date_expected, Cost_total_rub,
                        Supplier, Location, Source, Initial_doc_no
                    )
                    SELECT
                        t.ERP_ID, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 'deficit_supply', 'deficit_supply', v_tx_id,
                        'move', t.where_from, t.where_to, v_req_qty, 0, 'В ожидании',
                        t.Project, t.Target_assembly, t.Supplied_component_number, t.Component_revision, t.Component_name,
                        t.Quantity_in_target_assembly, t.Quantity_of_target_assemblies, t.Components_quantity_in_assembly, t.Component_type,
                        t.For_supplied_as_assembly_components_provided_by_supplier, t.Part_material, t.Producer, t.Catalogue_number,
                        t.Producer_article, t.Distributer, t.Distributer_article, t.MBOM_type, t.Mass_kg, t.Unit_of_measure,
                        t.Height, t.Width, t.Length, t.Advanced_group, t.Address,
                        t.Recommend_purchprod,
                        t.Order_purch, t.Order_wh, t.Order_prod, t.Order_OTK,
                        t.Order_sv, t.Recommend_wh, t.Quantity_ordered, t.Replace_to, t.Rework_to, t.Rework_from,
                        'Ожидание поставки', t.Document_no, t.Document_date, t.Zakaz_no, t.Date_needed, t.Date_expected, t.Cost_total_rub,
                        t.Supplier, t.Location, t.Source, t.Initial_doc_no
                    FROM `Transactions` t
                    WHERE t.id = v_tx_id;

                    INSERT INTO `Transactions` (
                        ERP_ID, created_at, updated_at, created_by, updated_by, linked_transaction,
                        type, where_from, where_to, Quantity_of_parts_total, Quantity_change, Status_transaction,
                        Project, Target_assembly, Supplied_component_number, Component_revision, Component_name,
                        Quantity_in_target_assembly, Quantity_of_target_assemblies, Components_quantity_in_assembly, Component_type,
                        For_supplied_as_assembly_components_provided_by_supplier, Part_material, Producer, Catalogue_number,
                        Producer_article, Distributer, Distributer_article, MBOM_type, Mass_kg, Unit_of_measure,
                        Height, Width, Length, Advanced_group, Address,
                        Recommend_purchprod,
                        Order_purch, Order_wh, Order_prod, Order_OTK,
                        Order_sv, Recommend_wh, Quantity_ordered, Replace_to, Rework_to, Rework_from,
                        Status_warehouse,
                        Document_no, Document_date, Zakaz_no, Date_needed, Date_expected, Cost_total_rub,
                        Supplier, Location, Source, Initial_doc_no
                    )
                    SELECT
                        t.ERP_ID, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 'deficit_supply', 'deficit_supply', v_tx_id,
                        'change', 'внешний', 'склад', 0, v_req_qty, 'В ожидании',
                        t.Project, t.Target_assembly, t.Supplied_component_number, t.Component_revision, t.Component_name,
                        t.Quantity_in_target_assembly, t.Quantity_of_target_assemblies, t.Components_quantity_in_assembly, t.Component_type,
                        t.For_supplied_as_assembly_components_provided_by_supplier, t.Part_material, t.Producer, t.Catalogue_number,
                        t.Producer_article, t.Distributer, t.Distributer_article, t.MBOM_type, t.Mass_kg, t.Unit_of_measure,
                        t.Height, t.Width, t.Length, t.Advanced_group, t.Address,
                        t.Recommend_purchprod,
                        t.Order_purch, t.Order_wh, t.Order_prod, t.Order_OTK,
                        t.Order_sv, t.Recommend_wh, t.Quantity_ordered, t.Replace_to, t.Rework_to, t.Rework_from,
                        'Новая', t.Document_no, t.Document_date, t.Zakaz_no, t.Date_needed, t.Date_expected, t.Cost_total_rub,
                        t.Supplier, t.Location, t.Source, t.Initial_doc_no
                    FROM `Transactions` t
                    WHERE t.id = v_tx_id;
                END IF;
            END LOOP row_loop;

            DELETE FROM tmp_deficit_supply_groups
            WHERE (project <=> v_project)
              AND (adv_group <=> v_adv_group)
            LIMIT 1;
        END LOOP group_loop;

        DROP TEMPORARY TABLE IF EXISTS tmp_deficit_supply_groups;
        COMMIT;
        DO RELEASE_LOCK('lock_process_move_deficit_supply');
    END IF;
END$$

DELIMITER ;
