-- rework: оформляет доработку запаса старой ревизии в новую ревизию.

DELIMITER $$

DROP PROCEDURE IF EXISTS `rework`$$

CREATE PROCEDURE `rework`(
  IN p_transaction_id INT UNSIGNED
)
BEGIN
  DECLARE v_old_qty BIGINT DEFAULT 0;
  DECLARE v_rework_from VARCHAR(255);
  DECLARE v_target_id INT UNSIGNED DEFAULT NULL;
  DECLARE v_target_qty BIGINT DEFAULT NULL;
  DECLARE v_split_source_id INT UNSIGNED DEFAULT NULL;
  DECLARE v_updated_by_max INT DEFAULT 2000;
  DECLARE v_assembly_batch_id VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL;
  DECLARE v_assembly_batch_name TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL;
  DECLARE v_source_component_name TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL;
  DECLARE v_source_component_revision TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL;
  DECLARE v_source_assembly_batch_id VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL;

  SELECT COALESCE(c.CHARACTER_MAXIMUM_LENGTH, 2000)
    INTO v_updated_by_max
  FROM information_schema.COLUMNS c
  WHERE c.TABLE_SCHEMA = DATABASE()
    AND c.TABLE_NAME = 'Transactions'
    AND c.COLUMN_NAME = 'updated_by'
  LIMIT 1;

  SELECT
      ABS(COALESCE(t.`Quantity_change`, 0)),
      CAST(t.`ERP_ID` AS CHAR),
      t.`Component_name`,
      t.`Component_revision`,
      t.`Assembly_batch_id`
    INTO
      v_old_qty,
      v_rework_from,
      v_source_component_name,
      v_source_component_revision,
      v_source_assembly_batch_id
  FROM `Transactions` t
  WHERE t.id = p_transaction_id
    AND t.`type` = 'change'
    AND COALESCE(t.`Quantity_change`, 0) < 0
  LIMIT 1;

  IF v_rework_from IS NOT NULL THEN
    IF v_source_assembly_batch_id IS NULL OR TRIM(COALESCE(v_source_assembly_batch_id, '')) = '' THEN
      CALL `assembly_batch_id_create`(v_assembly_batch_id);
    ELSE
      SET v_assembly_batch_id = v_source_assembly_batch_id;
    END IF;

    SET v_assembly_batch_name = CONCAT(
      'Доработка ',
      COALESCE(v_source_component_name, ''),
      ' ревизии ',
      COALESCE(v_source_component_revision, '')
    );
  END IF;

  SELECT t.id, COALESCE(t.`Quantity_change`, 0)
    INTO v_target_id, v_target_qty
  FROM `Transactions` t
  WHERE t.`type` = 'change'
    AND t.`where_from` = 'внешний'
    AND t.`where_to` = 'склад'
    AND COALESCE(t.`Quantity_change`, 0) > 0
    AND t.`Rework_from` COLLATE utf8mb4_unicode_ci = v_rework_from COLLATE utf8mb4_unicode_ci
    AND t.`Status_transaction` = 'В ожидании'
    AND t.`Status_warehouse` IN ('Новая', 'В закупке', 'В изготовлении')
  ORDER BY
    CASE WHEN COALESCE(t.`Quantity_change`, 0) = v_old_qty THEN 0 ELSE 1 END,
    COALESCE(t.`Quantity_change`, 0) DESC,
    t.id
  LIMIT 1;

  IF v_target_id IS NULL THEN
    UPDATE `Transactions`
    SET `Order_sv` = NULL,
        `updated_at` = CURRENT_TIMESTAMP
    WHERE id = p_transaction_id;
  ELSEIF v_old_qty = v_target_qty THEN
    UPDATE `Transactions` t
    SET
      t.`Status_warehouse` = 'Доработка',
      t.`Assembly_batch_id` = v_assembly_batch_id,
      t.`Assembly_batch_name` = v_assembly_batch_name,
      t.`Assembly_batch_status` = NULL,
      t.`Assembly_batch_priority` = NULL,
      t.`updated_by` = CASE WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'rework' ELSE LEFT(CONCAT(t.`updated_by`, '; ', 'rework'), v_updated_by_max) END,
      t.`updated_at` = CURRENT_TIMESTAMP
    WHERE t.id = v_target_id;

    INSERT INTO `Transactions` (
      ERP_ID, created_at, updated_at, created_by, updated_by, linked_transaction,
      type, where_from, where_to, Quantity_of_parts_total, Quantity_change, Status_transaction,
      Project, Target_assembly, Supplied_component_number, Component_revision, Component_name,
      Quantity_in_target_assembly, Quantity_of_target_assemblies, Components_quantity_in_assembly,
      Assembly_batch_id, Assembly_batch_name, Assembly_batch_status, Assembly_batch_priority,
      Component_type,
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
      v_rework_from, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 'rework', 'rework', CAST(p_transaction_id AS CHAR),
      'move', 'склад', 'доработка', v_target_qty, 0, 'В ожидании',
      t.Project, t.Target_assembly, t.Supplied_component_number, t.Component_revision, t.Component_name,
      t.Quantity_in_target_assembly, t.Quantity_of_target_assemblies, t.Components_quantity_in_assembly,
      v_assembly_batch_id, v_assembly_batch_name, NULL, NULL,
      t.Component_type,
      t.For_supplied_as_assembly_components_provided_by_supplier, t.Part_material, t.Producer, t.Catalogue_number,
      t.Producer_article, t.Distributer, t.Distributer_article, t.MBOM_type, t.Mass_kg, t.Unit_of_measure,
      t.Height, t.Width, t.Length, t.Advanced_group, t.Address,
      t.Recommend_purchprod,
      NULL, NULL, NULL, NULL,
      NULL, t.Recommend_wh, 0, t.Replace_to, t.Rework_to, t.Rework_from,
      'Новая',
      t.Document_no, t.Document_date, t.Zakaz_no, t.Date_needed, t.Date_expected, t.Cost_total_rub,
      t.Supplier, t.Location, t.Source, t.Initial_doc_no
    FROM `Transactions` t
    WHERE t.id = v_target_id;

    UPDATE `Transactions` t
    SET
      t.`Status_transaction` = 'Исполнено',
      t.`Order_sv` = NULL,
      t.`updated_by` = CASE WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'rework' ELSE LEFT(CONCAT(t.`updated_by`, '; ', 'rework'), v_updated_by_max) END,
      t.`updated_at` = CURRENT_TIMESTAMP
    WHERE t.id = p_transaction_id;
  ELSEIF v_old_qty < v_target_qty THEN
    SET v_split_source_id = v_target_id;
    CALL `split`(v_split_source_id, v_old_qty, 'доработать запас', NULL);

    SELECT COALESCE(MAX(t.id), 0)
      INTO v_target_id
    FROM `Transactions` t
    WHERE t.`type` = 'change'
      AND t.`where_from` = 'внешний'
      AND t.`where_to` = 'склад'
      AND COALESCE(t.`Quantity_change`, 0) = v_old_qty
      AND t.`Rework_from` COLLATE utf8mb4_unicode_ci = v_rework_from COLLATE utf8mb4_unicode_ci
      AND t.`Status_transaction` = 'В ожидании'
      AND t.`Status_warehouse` IN ('Новая', 'В закупке', 'В изготовлении')
      AND t.`created_by` = 'split'
      AND t.`Order_sv` = 'доработать запас'
      AND t.`linked_transaction` COLLATE utf8mb4_unicode_ci = CAST(v_split_source_id AS CHAR CHARACTER SET utf8mb4) COLLATE utf8mb4_unicode_ci;

    IF v_target_id = 0 THEN
      UPDATE `Transactions`
      SET `Order_sv` = NULL,
          `updated_at` = CURRENT_TIMESTAMP
      WHERE id = p_transaction_id;
    ELSE
      SET v_target_qty = v_old_qty;

      UPDATE `Transactions` t
      SET
        t.`Status_warehouse` = 'Доработка',
        t.`Assembly_batch_id` = v_assembly_batch_id,
        t.`Assembly_batch_name` = v_assembly_batch_name,
        t.`Assembly_batch_status` = NULL,
        t.`Assembly_batch_priority` = NULL,
        t.`updated_by` = CASE WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'rework' ELSE LEFT(CONCAT(t.`updated_by`, '; ', 'rework'), v_updated_by_max) END,
        t.`updated_at` = CURRENT_TIMESTAMP
      WHERE t.id = v_target_id;

      INSERT INTO `Transactions` (
        ERP_ID, created_at, updated_at, created_by, updated_by, linked_transaction,
        type, where_from, where_to, Quantity_of_parts_total, Quantity_change, Status_transaction,
        Project, Target_assembly, Supplied_component_number, Component_revision, Component_name,
        Quantity_in_target_assembly, Quantity_of_target_assemblies, Components_quantity_in_assembly,
        Assembly_batch_id, Assembly_batch_name, Assembly_batch_status, Assembly_batch_priority,
        Component_type,
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
        v_rework_from, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 'rework', 'rework', CAST(p_transaction_id AS CHAR),
        'move', 'склад', 'доработка', v_target_qty, 0, 'В ожидании',
        t.Project, t.Target_assembly, t.Supplied_component_number, t.Component_revision, t.Component_name,
        t.Quantity_in_target_assembly, t.Quantity_of_target_assemblies, t.Components_quantity_in_assembly,
        v_assembly_batch_id, v_assembly_batch_name, NULL, NULL,
        t.Component_type,
        t.For_supplied_as_assembly_components_provided_by_supplier, t.Part_material, t.Producer, t.Catalogue_number,
        t.Producer_article, t.Distributer, t.Distributer_article, t.MBOM_type, t.Mass_kg, t.Unit_of_measure,
        t.Height, t.Width, t.Length, t.Advanced_group, t.Address,
        t.Recommend_purchprod,
        NULL, NULL, NULL, NULL,
        NULL, t.Recommend_wh, 0, t.Replace_to, t.Rework_to, t.Rework_from,
        'Новая',
        t.Document_no, t.Document_date, t.Zakaz_no, t.Date_needed, t.Date_expected, t.Cost_total_rub,
        t.Supplier, t.Location, t.Source, t.Initial_doc_no
      FROM `Transactions` t
      WHERE t.id = v_target_id;

      UPDATE `Transactions` t
      SET
        t.`Status_transaction` = 'Исполнено',
        t.`Order_sv` = NULL,
        t.`updated_by` = CASE WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'rework' ELSE LEFT(CONCAT(t.`updated_by`, '; ', 'rework'), v_updated_by_max) END,
        t.`updated_at` = CURRENT_TIMESTAMP
      WHERE t.id = p_transaction_id;
    END IF;
  ELSE
    CALL `split`(p_transaction_id, v_target_qty, 'доработать запас', NULL);

    UPDATE `Transactions` t
    SET
      t.`Assembly_batch_id` = v_assembly_batch_id,
      t.`Assembly_batch_name` = v_assembly_batch_name,
      t.`Assembly_batch_status` = NULL,
      t.`Assembly_batch_priority` = NULL,
      t.`updated_by` = CASE WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'rework' ELSE LEFT(CONCAT(t.`updated_by`, '; ', 'rework'), v_updated_by_max) END,
      t.`updated_at` = CURRENT_TIMESTAMP
    WHERE t.`type` = 'change'
      AND t.`created_by` = 'split'
      AND t.`Order_sv` = 'доработать запас'
      AND t.`linked_transaction` COLLATE utf8mb4_unicode_ci = CAST(p_transaction_id AS CHAR CHARACTER SET utf8mb4) COLLATE utf8mb4_unicode_ci;
  END IF;
END$$

DELIMITER ;
