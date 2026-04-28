-- replace_new: отменяет move/change-строку и создает заменяющие строки с ERP_ID = Replace_to.

DELIMITER $$

DROP PROCEDURE IF EXISTS `replace_new`$$

CREATE PROCEDURE `replace_new`(
  IN p_transaction_id INT UNSIGNED
)
BEGIN
  DECLARE v_type VARCHAR(16);
  DECLARE v_status_wh VARCHAR(64);
  DECLARE v_replace_to VARCHAR(255);
  DECLARE v_updated_by_max INT DEFAULT 2000;

  SELECT COALESCE(c.CHARACTER_MAXIMUM_LENGTH, 2000)
    INTO v_updated_by_max
  FROM information_schema.COLUMNS c
  WHERE c.TABLE_SCHEMA = DATABASE()
    AND c.TABLE_NAME = 'Transactions'
    AND c.COLUMN_NAME = 'updated_by'
  LIMIT 1;

  SELECT t.`type`, t.`Status_warehouse`, CAST(t.`Replace_to` AS CHAR)
    INTO v_type, v_status_wh, v_replace_to
  FROM `Transactions` t
  WHERE t.id = p_transaction_id
  LIMIT 1;

  IF v_type = 'move' THEN
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
      v_replace_to, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 'replace_new', 'replace_new', CAST(t.id AS CHAR),
      'move', t.where_from, t.where_to, t.Quantity_of_parts_total, t.Quantity_change, 'В ожидании',
      t.Project, t.Target_assembly, t.Supplied_component_number, t.Component_revision, t.Component_name,
      t.Quantity_in_target_assembly, t.Quantity_of_target_assemblies, t.Components_quantity_in_assembly, t.Component_type,
      t.For_supplied_as_assembly_components_provided_by_supplier, t.Part_material, t.Producer, t.Catalogue_number,
      t.Producer_article, t.Distributer, t.Distributer_article, t.MBOM_type, t.Mass_kg, t.Unit_of_measure,
      t.Height, t.Width, t.Length, t.Advanced_group, t.Address,
      t.Recommend_purchprod,
      t.Order_purch, t.Order_wh, t.Order_prod, t.Order_OTK,
      NULL, t.Recommend_wh, t.Quantity_ordered, t.Replace_to, t.Rework_to, t.Rework_from,
      t.Status_warehouse,
      t.Document_no, t.Document_date, t.Zakaz_no, t.Date_needed, t.Date_expected, t.Cost_total_rub,
      t.Supplier, t.Location, t.Source, t.Initial_doc_no
    FROM `Transactions` t
    WHERE t.id = p_transaction_id;

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
      v_replace_to, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 'replace_new', 'replace_new', CAST(t.id AS CHAR),
      'change', 'внешний', 'склад', 0, t.Quantity_of_parts_total, 'В ожидании',
      t.Project, t.Target_assembly, t.Supplied_component_number, t.Component_revision, t.Component_name,
      t.Quantity_in_target_assembly, t.Quantity_of_target_assemblies, t.Components_quantity_in_assembly, t.Component_type,
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
    WHERE t.id = p_transaction_id;

    UPDATE `Transactions` t
    SET t.`Status_transaction` = 'Отменено',
        t.`linked_transaction` = CASE WHEN t.`linked_transaction` IS NULL OR TRIM(COALESCE(t.`linked_transaction`, '')) = '' THEN CAST(p_transaction_id AS CHAR) ELSE CONCAT(TRIM(t.`linked_transaction`), '; ', p_transaction_id) END,
        t.`updated_by` = CASE WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'replace_new' ELSE LEFT(CONCAT(t.`updated_by`, '; ', 'replace_new'), v_updated_by_max) END,
        t.`updated_at` = CURRENT_TIMESTAMP
    WHERE t.id = p_transaction_id;

  ELSEIF v_type = 'change' AND v_status_wh IN ('Новая', 'В закупке', 'В изготовлении') THEN
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
      v_replace_to, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 'replace_new', 'replace_new', CAST(t.id AS CHAR),
      'change', t.where_from, t.where_to, t.Quantity_of_parts_total, t.Quantity_change, 'В ожидании',
      t.Project, t.Target_assembly, t.Supplied_component_number, t.Component_revision, t.Component_name,
      t.Quantity_in_target_assembly, t.Quantity_of_target_assemblies, t.Components_quantity_in_assembly, t.Component_type,
      t.For_supplied_as_assembly_components_provided_by_supplier, t.Part_material, t.Producer, t.Catalogue_number,
      t.Producer_article, t.Distributer, t.Distributer_article, t.MBOM_type, t.Mass_kg, t.Unit_of_measure,
      t.Height, t.Width, t.Length, t.Advanced_group, t.Address,
      t.Recommend_purchprod,
      NULL, NULL, NULL, NULL,
      NULL, t.Recommend_wh, 0, t.Replace_to, t.Rework_to, t.Rework_from,
      t.Status_warehouse,
      t.Document_no, t.Document_date, t.Zakaz_no, t.Date_needed, t.Date_expected, t.Cost_total_rub,
      t.Supplier, t.Location, t.Source, t.Initial_doc_no
    FROM `Transactions` t
    WHERE t.id = p_transaction_id;

    UPDATE `Transactions` t
    SET t.`Status_transaction` = 'Отменено',
        t.`linked_transaction` = CASE WHEN t.`linked_transaction` IS NULL OR TRIM(COALESCE(t.`linked_transaction`, '')) = '' THEN CAST(p_transaction_id AS CHAR) ELSE CONCAT(TRIM(t.`linked_transaction`), '; ', p_transaction_id) END,
        t.`updated_by` = CASE WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'replace_new' ELSE LEFT(CONCAT(t.`updated_by`, '; ', 'replace_new'), v_updated_by_max) END,
        t.`updated_at` = CURRENT_TIMESTAMP
    WHERE t.id = p_transaction_id;
  ELSE
    UPDATE `Transactions` SET `Order_sv` = NULL WHERE id = p_transaction_id;
  END IF;
END$$

DELIMITER ;
