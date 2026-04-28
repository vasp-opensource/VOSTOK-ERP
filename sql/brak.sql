-- brak: бракует складские остатки на основании отрицательной change-строки.

DELIMITER $$

DROP PROCEDURE IF EXISTS `brak`$$

CREATE PROCEDURE `brak`(
  IN p_transaction_id INT UNSIGNED
)
BEGIN
  DECLARE v_updated_by_max INT DEFAULT 2000;

  SELECT COALESCE(c.CHARACTER_MAXIMUM_LENGTH, 2000)
    INTO v_updated_by_max
  FROM information_schema.COLUMNS c
  WHERE c.TABLE_SCHEMA = DATABASE()
    AND c.TABLE_NAME = 'Transactions'
    AND c.COLUMN_NAME = 'updated_by'
  LIMIT 1;

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
    t.ERP_ID, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 'brak', 'brak', CAST(t.id AS CHAR),
    'move', 'склад', 'брак', COALESCE(t.Quantity_change, 0), 0, 'В ожидании',
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
  WHERE t.id = p_transaction_id
    AND t.`type` = 'change'
    AND COALESCE(t.`Quantity_change`, 0) < 0;

  UPDATE `Transactions` t
  SET
    t.`Status_warehouse` = 'Утилизация',
    t.`Status_transaction` = 'Отменено',
    t.`Order_sv` = NULL,
    t.`updated_by` = CASE
      WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'brak'
      ELSE LEFT(CONCAT(t.`updated_by`, '; ', 'brak'), v_updated_by_max)
    END,
    t.`updated_at` = CURRENT_TIMESTAMP
  WHERE t.id = p_transaction_id
    AND t.`type` = 'change'
    AND COALESCE(t.`Quantity_change`, 0) < 0;
END$$

DELIMITER ;
