DELIMITER $$

DROP PROCEDURE IF EXISTS replace_wh$$

CREATE PROCEDURE replace_wh(
  IN p_source_transaction_id BIGINT
)
proc: BEGIN
  DECLARE v_proc_name VARCHAR(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT 'replace_wh';

  DECLARE v_source_id BIGINT DEFAULT NULL;
  DECLARE v_source_erp_id VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL;
  DECLARE v_source_type VARCHAR(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL;
  DECLARE v_replace_to VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL;
  DECLARE v_source_where_from VARCHAR(128) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL;
  DECLARE v_source_where_to VARCHAR(128) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL;
  DECLARE v_source_qty_total DECIMAL(18,6) DEFAULT 0;
  DECLARE v_source_status_transaction VARCHAR(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL;
  DECLARE v_source_status_warehouse VARCHAR(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL;
  DECLARE v_source_order_purch VARCHAR(128) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL;
  DECLARE v_source_order_wh VARCHAR(128) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL;
  DECLARE v_source_order_prod VARCHAR(128) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL;
  DECLARE v_source_order_otk VARCHAR(128) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL;

  DECLARE v_quantity_available DECIMAL(18,6) DEFAULT 0;
  DECLARE v_quantity_replaced DECIMAL(18,6) DEFAULT 0;
  DECLARE v_split_from DATETIME(6) DEFAULT NULL;
  DECLARE v_created_from DATETIME(6) DEFAULT NULL;
  DECLARE v_new_id BIGINT DEFAULT NULL;
  DECLARE v_return_id BIGINT DEFAULT NULL;
  DECLARE v_link_token VARCHAR(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL;

  SELECT
    t.id,
    t.ERP_ID,
    t.type,
    t.Replace_to,
    t.where_from,
    t.where_to,
    COALESCE(t.Quantity_of_parts_total, 0),
    t.Status_transaction,
    t.Status_warehouse,
    t.Order_purch,
    t.Order_wh,
    t.Order_prod,
    t.Order_OTK
  INTO
    v_source_id,
    v_source_erp_id,
    v_source_type,
    v_replace_to,
    v_source_where_from,
    v_source_where_to,
    v_source_qty_total,
    v_source_status_transaction,
    v_source_status_warehouse,
    v_source_order_purch,
    v_source_order_wh,
    v_source_order_prod,
    v_source_order_otk
  FROM Transactions t
  WHERE t.id = p_source_transaction_id
  LIMIT 1;

  IF v_source_id IS NULL OR v_source_type <> 'move' OR v_replace_to IS NULL THEN
    LEAVE proc;
  END IF;

  SET v_quantity_replaced = v_source_qty_total;

  SELECT COALESCE(m.Quantity_in_warehouse, 0)
  INTO v_quantity_available
  FROM Main m
  WHERE m.ERP_ID COLLATE utf8mb4_unicode_ci = v_replace_to COLLATE utf8mb4_unicode_ci
  LIMIT 1;

  IF v_quantity_available < v_quantity_replaced THEN
    SET v_split_from = NOW(6);
    CALL split(v_source_id, v_quantity_available, NULL, NULL);

    SELECT t.id, COALESCE(t.Quantity_of_parts_total, 0)
    INTO v_source_id, v_quantity_replaced
    FROM Transactions t
    WHERE t.created_by = 'split'
      AND t.type = 'move'
      AND t.linked_transaction COLLATE utf8mb4_unicode_ci = CAST(p_source_transaction_id AS CHAR CHARACTER SET utf8mb4) COLLATE utf8mb4_unicode_ci
      AND t.created_at >= v_split_from
    ORDER BY t.created_at ASC, t.id ASC
    LIMIT 1;
  END IF;

  IF v_source_id IS NULL OR v_quantity_replaced <= 0 THEN
    LEAVE proc;
  END IF;

  IF v_quantity_available >= v_quantity_replaced THEN
    SET v_link_token = CAST(v_source_id AS CHAR);
    SET v_created_from = NOW(6);

    CALL create_row(
      v_source_id,
      'move',
      v_source_where_from,
      v_source_where_to,
      v_quantity_replaced,
      0,
      v_source_status_transaction,
      'Новая',
      v_source_order_purch,
      v_source_order_wh,
      v_source_order_prod,
      v_source_order_otk,
      NULL
    );

    SELECT t.id
    INTO v_new_id
    FROM Transactions t
    WHERE t.created_by = 'create_row'
      AND t.type = 'move'
      AND t.ERP_ID COLLATE utf8mb4_unicode_ci = v_replace_to COLLATE utf8mb4_unicode_ci
      AND t.linked_transaction COLLATE utf8mb4_unicode_ci = CAST(v_source_id AS CHAR CHARACTER SET utf8mb4) COLLATE utf8mb4_unicode_ci
      AND t.created_at >= v_created_from
    ORDER BY t.created_at DESC, t.id DESC
    LIMIT 1;

    IF v_source_status_warehouse IN ('Сборка', 'Упаковка', 'Утилизация', 'Доработка') THEN
      INSERT INTO Transactions (
        ERP_ID,
        created_at,
        updated_at,
        created_by,
        updated_by,
        linked_transaction,
        type,
        where_from,
        where_to,
        Quantity_of_parts_total,
        Quantity_change,
        Status_transaction,
        Status_warehouse,
        Project,
        Target_assembly,
        Supplied_component_number,
        Component_revision,
        Component_name,
        Quantity_in_target_assembly,
        Quantity_of_target_assemblies,
        Component_type,
        For_supplied_as_assembly_components_provided_by_supplier,
        Components_quantity_in_assembly,
        Assembly_batch_id,
        Assembly_batch_name,
        Assembly_batch_status,
        Assembly_batch_priority,
        Part_material,
        Producer,
        Catalogue_number,
        Producer_article,
        Distributer,
        Distributer_article,
        MBOM_type,
        Mass_kg,
        Unit_of_measure,
        Height,
        Width,
        Length,
        Advanced_group,
        Address,
        Recommend_purchprod,
        Order_purch,
        Order_wh,
        Order_prod,
        Order_OTK,
        Order_sv,
        Recommend_wh,
        Quantity_ordered,
        Replace_to,
        Rework_to,
        Rework_from,
        Document_no,
        Document_date,
        Zakaz_no,
        Date_needed,
        Date_expected,
        Cost_total_rub,
        Supplier,
        Location,
        Source,
        Initial_doc_no
      )
      SELECT
        t.ERP_ID,
        NOW(),
        NOW(),
        v_proc_name,
        v_proc_name,
        NULL,
        'move',
        'цех',
        'склад',
        v_quantity_replaced,
        0,
        t.Status_transaction,
        t.Status_warehouse,
        t.Project,
        t.Target_assembly,
        t.Supplied_component_number,
        t.Component_revision,
        t.Component_name,
        t.Quantity_in_target_assembly,
        t.Quantity_of_target_assemblies,
        t.Component_type,
        t.For_supplied_as_assembly_components_provided_by_supplier,
        t.Components_quantity_in_assembly,
        t.Assembly_batch_id,
        t.Assembly_batch_name,
        t.Assembly_batch_status,
        t.Assembly_batch_priority,
        t.Part_material,
        t.Producer,
        t.Catalogue_number,
        t.Producer_article,
        t.Distributer,
        t.Distributer_article,
        t.MBOM_type,
        t.Mass_kg,
        t.Unit_of_measure,
        t.Height,
        t.Width,
        t.Length,
        t.Advanced_group,
        t.Address,
        t.Recommend_purchprod,
        t.Order_purch,
        t.Order_wh,
        t.Order_prod,
        t.Order_OTK,
        NULL,
        t.Recommend_wh,
        t.Quantity_ordered,
        NULL,
        t.Rework_to,
        t.Rework_from,
        t.Document_no,
        t.Document_date,
        t.Zakaz_no,
        t.Date_needed,
        t.Date_expected,
        t.Cost_total_rub,
        t.Supplier,
        t.Location,
        t.Source,
        t.Initial_doc_no
      FROM Transactions t
      WHERE t.id = v_source_id;

      SET v_return_id = LAST_INSERT_ID();
    END IF;

    UPDATE Transactions
    SET
      Status_transaction = 'Заменен ID',
      updated_at = NOW(),
      updated_by = CASE
        WHEN updated_by IS NULL OR TRIM(updated_by) = '' THEN v_proc_name
        ELSE CONCAT(TRIM(TRAILING ';' FROM TRIM(updated_by)), '; ', v_proc_name)
      END,
      linked_transaction = CASE
        WHEN linked_transaction IS NULL OR TRIM(linked_transaction) = '' THEN v_link_token
        ELSE CONCAT(TRIM(TRAILING ';' FROM TRIM(linked_transaction)), '; ', v_link_token)
      END
    WHERE id = v_source_id;

    UPDATE Main
    SET
      inProcess_purchase = CASE
        WHEN v_source_status_warehouse = 'В закупке'
          THEN COALESCE(inProcess_purchase, 0) - COALESCE(v_quantity_replaced, 0)
        ELSE inProcess_purchase
      END,
      inProcess_manufacturing = CASE
        WHEN v_source_status_warehouse = 'В изготовлении'
          THEN COALESCE(inProcess_manufacturing, 0) - COALESCE(v_quantity_replaced, 0)
        ELSE inProcess_manufacturing
      END,
      Quantity_in_kitting = CASE
        WHEN v_source_status_warehouse = 'Комплектация'
          THEN COALESCE(Quantity_in_kitting, 0) - COALESCE(v_quantity_replaced, 0)
        ELSE Quantity_in_kitting
      END,
      Quantity_in_warehouse = CASE
        WHEN v_source_status_warehouse = 'Комплектация'
          THEN COALESCE(Quantity_in_warehouse, 0) + COALESCE(v_quantity_replaced, 0)
        ELSE Quantity_in_warehouse
      END
    WHERE ERP_ID COLLATE utf8mb4_unicode_ci = v_source_erp_id COLLATE utf8mb4_unicode_ci
      AND v_source_status_warehouse IN ('В закупке', 'В изготовлении', 'Комплектация');

    IF v_new_id IS NOT NULL THEN
      UPDATE Transactions
      SET
        linked_transaction = CASE
          WHEN linked_transaction IS NULL OR TRIM(linked_transaction) = '' THEN v_link_token
          ELSE CONCAT(TRIM(TRAILING ';' FROM TRIM(linked_transaction)), '; ', v_link_token)
        END,
        updated_at = NOW(),
        updated_by = CASE
          WHEN updated_by IS NULL OR TRIM(updated_by) = '' THEN v_proc_name
          ELSE CONCAT(TRIM(TRAILING ';' FROM TRIM(updated_by)), '; ', v_proc_name)
        END
      WHERE id = v_new_id;
    END IF;

    IF v_return_id IS NOT NULL THEN
      UPDATE Transactions
      SET
        linked_transaction = CASE
          WHEN linked_transaction IS NULL OR TRIM(linked_transaction) = '' THEN v_link_token
          ELSE CONCAT(TRIM(TRAILING ';' FROM TRIM(linked_transaction)), '; ', v_link_token)
        END,
        updated_at = NOW(),
        updated_by = CASE
          WHEN updated_by IS NULL OR TRIM(updated_by) = '' THEN v_proc_name
          ELSE CONCAT(TRIM(TRAILING ';' FROM TRIM(updated_by)), '; ', v_proc_name)
        END
      WHERE id = v_return_id;
    END IF;
  END IF;
END$$

DELIMITER ;
