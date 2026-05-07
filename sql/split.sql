-- split: заменяет одну строку Transactions двумя строками с разделенным количеством.

DELIMITER $$

DROP PROCEDURE IF EXISTS `split`$$

CREATE PROCEDURE `split`(
  IN p_transaction_id INT UNSIGNED,
  IN p_quantity_ordered BIGINT,
  IN p_order_sv_1 VARCHAR(64),
  IN p_order_sv_2 VARCHAR(64)
)
BEGIN
  DECLARE v_type VARCHAR(16);
  DECLARE v_qty_total BIGINT DEFAULT 0;
  DECLARE v_qty_change BIGINT DEFAULT 0;
  DECLARE v_updated_by_max INT DEFAULT 2000;

  SELECT COALESCE(c.CHARACTER_MAXIMUM_LENGTH, 2000)
    INTO v_updated_by_max
  FROM information_schema.COLUMNS c
  WHERE c.TABLE_SCHEMA = DATABASE()
    AND c.TABLE_NAME = 'Transactions'
    AND c.COLUMN_NAME = 'updated_by'
  LIMIT 1;

  SELECT t.`type`, COALESCE(t.`Quantity_of_parts_total`, 0), COALESCE(t.`Quantity_change`, 0)
    INTO v_type, v_qty_total, v_qty_change
  FROM `Transactions` t
  WHERE t.id = p_transaction_id
  LIMIT 1;

  IF v_type IN ('change', 'move') AND p_quantity_ordered IS NOT NULL THEN
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
      Document_no, Document_date, Document_id, Zakaz_no, Date_needed, Date_expected, Cost_total_rub,
      Supplier, Contractor_id, Location, Source, Initial_doc_no
    )
    SELECT
      t.ERP_ID, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 'split', 'split', CAST(p_transaction_id AS CHAR),
      t.type, t.where_from, t.where_to,
      CASE WHEN v_type = 'move' THEN p_quantity_ordered ELSE t.Quantity_of_parts_total END,
      CASE
        WHEN v_type = 'change' AND v_qty_change < 0 THEN -1 * p_quantity_ordered
        WHEN v_type = 'change' THEN p_quantity_ordered
        ELSE t.Quantity_change
      END,
      'В ожидании',
      t.Project, t.Target_assembly, t.Supplied_component_number, t.Component_revision, t.Component_name,
      t.Quantity_in_target_assembly, t.Quantity_of_target_assemblies, t.Components_quantity_in_assembly,
      t.Assembly_batch_id, t.Assembly_batch_name, t.Assembly_batch_status, t.Assembly_batch_priority,
      t.Component_type,
      t.For_supplied_as_assembly_components_provided_by_supplier, t.Part_material, t.Producer, t.Catalogue_number,
      t.Producer_article, t.Distributer, t.Distributer_article, t.MBOM_type, t.Mass_kg, t.Unit_of_measure,
      t.Height, t.Width, t.Length, t.Advanced_group, t.Address,
      t.Recommend_purchprod,
      t.Order_purch, t.Order_wh, t.Order_prod, t.Order_OTK,
      NULLIF(p_order_sv_1, ''), t.Recommend_wh, t.Quantity_ordered, t.Replace_to, t.Rework_to, t.Rework_from,
      t.Status_warehouse,
      t.Document_no, t.Document_date, t.Document_id, t.Zakaz_no, t.Date_needed, t.Date_expected, t.Cost_total_rub,
      t.Supplier, t.Contractor_id, t.Location, t.Source, t.Initial_doc_no
    FROM `Transactions` t
    WHERE t.id = p_transaction_id;

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
      Document_no, Document_date, Document_id, Zakaz_no, Date_needed, Date_expected, Cost_total_rub,
      Supplier, Contractor_id, Location, Source, Initial_doc_no
    )
    SELECT
      t.ERP_ID, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 'split', 'split', CAST(p_transaction_id AS CHAR),
      t.type, t.where_from, t.where_to,
      CASE WHEN v_type = 'move' THEN v_qty_total - p_quantity_ordered ELSE t.Quantity_of_parts_total END,
      CASE
        WHEN v_type = 'change' AND v_qty_change < 0 THEN v_qty_change + p_quantity_ordered
        WHEN v_type = 'change' THEN v_qty_change - p_quantity_ordered
        ELSE t.Quantity_change
      END,
      'В ожидании',
      t.Project, t.Target_assembly, t.Supplied_component_number, t.Component_revision, t.Component_name,
      t.Quantity_in_target_assembly, t.Quantity_of_target_assemblies, t.Components_quantity_in_assembly,
      t.Assembly_batch_id, t.Assembly_batch_name, t.Assembly_batch_status, t.Assembly_batch_priority,
      t.Component_type,
      t.For_supplied_as_assembly_components_provided_by_supplier, t.Part_material, t.Producer, t.Catalogue_number,
      t.Producer_article, t.Distributer, t.Distributer_article, t.MBOM_type, t.Mass_kg, t.Unit_of_measure,
      t.Height, t.Width, t.Length, t.Advanced_group, t.Address,
      t.Recommend_purchprod,
      t.Order_purch, t.Order_wh, t.Order_prod, t.Order_OTK,
      NULLIF(p_order_sv_2, ''), t.Recommend_wh, t.Quantity_ordered, t.Replace_to, t.Rework_to, t.Rework_from,
      t.Status_warehouse,
      t.Document_no, t.Document_date, t.Document_id, t.Zakaz_no, t.Date_needed, t.Date_expected, t.Cost_total_rub,
      t.Supplier, t.Contractor_id, t.Location, t.Source, t.Initial_doc_no
    FROM `Transactions` t
    WHERE t.id = p_transaction_id;

    UPDATE `Transactions` t
    SET
      t.`Status_transaction` = 'Заменено',
      t.`linked_transaction` = CASE
        WHEN t.`linked_transaction` IS NULL OR TRIM(COALESCE(t.`linked_transaction`, '')) = '' THEN CAST(p_transaction_id AS CHAR)
        ELSE CONCAT(TRIM(t.`linked_transaction`), '; ', p_transaction_id)
      END,
      t.`updated_by` = CASE
        WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'split'
        ELSE LEFT(CONCAT(t.`updated_by`, '; ', 'split'), v_updated_by_max)
      END,
      t.`updated_at` = CURRENT_TIMESTAMP
    WHERE t.id = p_transaction_id;
  END IF;
END$$

DELIMITER ;
