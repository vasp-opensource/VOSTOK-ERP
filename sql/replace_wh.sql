-- replace_wh: отменяет move-строку и создает заменяющую move-строку с ERP_ID = Replace_to.

DELIMITER $$

DROP PROCEDURE IF EXISTS `replace_wh`$$

CREATE PROCEDURE `replace_wh`(
  IN p_transaction_id INT UNSIGNED
)
BEGIN
  DECLARE v_replace_to VARCHAR(255);
  DECLARE v_qty BIGINT DEFAULT 0;
  DECLARE v_wh_qty BIGINT DEFAULT 0;
  DECLARE v_source_id INT UNSIGNED DEFAULT NULL;
  DECLARE v_updated_by_max INT DEFAULT 2000;

  SELECT COALESCE(c.CHARACTER_MAXIMUM_LENGTH, 2000)
    INTO v_updated_by_max
  FROM information_schema.COLUMNS c
  WHERE c.TABLE_SCHEMA = DATABASE()
    AND c.TABLE_NAME = 'Transactions'
    AND c.COLUMN_NAME = 'updated_by'
  LIMIT 1;

  SELECT CAST(t.`Replace_to` AS CHAR), COALESCE(t.`Quantity_of_parts_total`, 0)
    INTO v_replace_to, v_qty
  FROM `Transactions` t
  WHERE t.id = p_transaction_id
  LIMIT 1;

  SELECT COALESCE(MAX(m.`Quantity_in_warehouse`), 0)
    INTO v_wh_qty
  FROM `Main` m
  WHERE m.`ERP_ID` COLLATE utf8mb4_unicode_ci = v_replace_to COLLATE utf8mb4_unicode_ci;

  SET v_source_id = p_transaction_id;

  IF v_wh_qty < v_qty THEN
    CALL `split`(p_transaction_id, v_wh_qty, 'разбить', NULL);

    SELECT COALESCE(MAX(t.id), 0)
      INTO v_source_id
    FROM `Transactions` t
    WHERE t.`type` = 'move'
      AND COALESCE(t.`Quantity_of_parts_total`, 0) = v_wh_qty
      AND t.`Status_transaction` = 'В ожидании'
      AND t.`created_by` = 'split'
      AND t.`linked_transaction` COLLATE utf8mb4_unicode_ci = CAST(p_transaction_id AS CHAR CHARACTER SET utf8mb4) COLLATE utf8mb4_unicode_ci;

    SET v_qty = v_wh_qty;
  END IF;

  IF v_source_id IS NOT NULL AND v_source_id <> 0 AND v_wh_qty >= v_qty THEN
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
      v_replace_to, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 'replace_wh', 'replace_wh', CAST(t.id AS CHAR),
      t.type, t.where_from, t.where_to, t.Quantity_of_parts_total, t.Quantity_change, 'В ожидании',
      t.Project, t.Target_assembly, t.Supplied_component_number, t.Component_revision, t.Component_name,
      t.Quantity_in_target_assembly, t.Quantity_of_target_assemblies, t.Components_quantity_in_assembly, t.Component_type,
      t.For_supplied_as_assembly_components_provided_by_supplier, t.Part_material, t.Producer, t.Catalogue_number,
      t.Producer_article, t.Distributer, t.Distributer_article, t.MBOM_type, t.Mass_kg, t.Unit_of_measure,
      t.Height, t.Width, t.Length, t.Advanced_group, t.Address,
      t.Recommend_purchprod,
      t.Order_purch, t.Order_wh, t.Order_prod, t.Order_OTK,
      NULL, NULL, t.Quantity_ordered, NULL, t.Rework_to, t.Rework_from,
      t.Status_warehouse,
      t.Document_no, t.Document_date, t.Zakaz_no, t.Date_needed, t.Date_expected, t.Cost_total_rub,
      t.Supplier, t.Location, t.Source, t.Initial_doc_no
    FROM `Transactions` t
    WHERE t.id = v_source_id
      AND t.`type` = 'move';

    UPDATE `Transactions` t
    SET
      t.`Status_transaction` = 'Отменено',
      t.`linked_transaction` = CASE
        WHEN t.`linked_transaction` IS NULL OR TRIM(COALESCE(t.`linked_transaction`, '')) = '' THEN CAST(v_source_id AS CHAR)
        ELSE CONCAT(TRIM(t.`linked_transaction`), '; ', v_source_id)
      END,
      t.`updated_by` = CASE
        WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'replace_wh'
        ELSE LEFT(CONCAT(t.`updated_by`, '; ', 'replace_wh'), v_updated_by_max)
      END,
      t.`updated_at` = CURRENT_TIMESTAMP
    WHERE t.id = v_source_id;
  END IF;
END$$

DELIMITER ;
