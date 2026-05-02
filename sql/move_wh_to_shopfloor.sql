-- move_wh_to_shopfloor: (1) move склад→брак|доработка|отгрузка|изделие; (2) объединение change по Advanced_group.
-- Порядок: сначала move (приоритет: брак → доработка → отгрузка → изделие), затем объединение change.
-- Блокировка: lock_move_wh_to_shopfloor (ожидание до 30 с).
-- Колонка Imported в Transactions не используется (нет в схеме).
--
-- Отбор move: where_to только «брак», «доработка», «отгрузка», «изделие»; Status_warehouse = «Новая».
-- При Order_wh = «В комплектации» задаётся Status_warehouse = «Комплектация» (полное и частичное списание со склада).
-- Source: копируется с родителя в дочерние move; в объединённом change — «Разные», если в группе разные Source, иначе общее значение.
-- Объединение change только со складом «Новая» или «Дефицит закупки» (как вход в ch_outside_to_purch): иначе в сумму попадают
-- лишние строки и строки от deficit за прошлые циклы → завышение Quantity_change (напр. 151 вместо 50).
-- Агрегированный change: после вставки в linked_transaction дописывается id новой строки (агрегат «голова» группы).
-- Заменённые родительские change: в linked_transaction дописывается id суммарной строки; Status_transaction = «Заменено».

DELIMITER $$

DROP PROCEDURE IF EXISTS move_wh_to_shopfloor$$

CREATE PROCEDURE move_wh_to_shopfloor()
BEGIN
  DECLARE v_lock_ok INT DEFAULT 0;
  DECLARE v_done INT DEFAULT 0;
  DECLARE v_id INT UNSIGNED;
  DECLARE v_erp_id VARCHAR(255);
  DECLARE v_need BIGINT;
  DECLARE v_wh BIGINT;
  DECLARE v_parent_id INT UNSIGNED;
  DECLARE v_where_to VARCHAR(32);

  DECLARE v_merge_left INT DEFAULT 0;
  DECLARE v_qid INT UNSIGNED;
  DECLARE v_m_erp VARCHAR(255);
  DECLARE v_m_ag_key TEXT;
  DECLARE v_m_sum BIGINT;
  DECLARE v_m_src VARCHAR(255);
  DECLARE v_m_new_id INT UNSIGNED;

  DECLARE cur CURSOR FOR
    SELECT
      id,
      ERP_ID,
      IF(COALESCE(Quantity_of_parts_total, 0) > 0, Quantity_of_parts_total, COALESCE(Quantity_change, 0)) AS need_qty,
      where_to
    FROM Transactions
    WHERE type = 'move'
      AND where_from = 'склад'
      AND where_to IN ('брак', 'доработка', 'отгрузка', 'изделие')
      AND (
           Status_transaction IS NULL
        OR TRIM(COALESCE(Status_transaction, '')) = ''
        OR Status_transaction = 'В ожидании'
      )
      AND (Order_wh IS NULL OR Order_wh = 'В комплектации')
      AND Status_warehouse = 'Новая'
    ORDER BY FIELD(where_to, 'брак', 'доработка', 'отгрузка', 'изделие'), id;

  DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = 1;

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    IF v_lock_ok = 1 THEN
      DO RELEASE_LOCK('lock_move_wh_to_shopfloor');
    END IF;
    RESIGNAL;
  END;

  SELECT GET_LOCK('lock_move_wh_to_shopfloor', 30) INTO v_lock_ok;


  IF COALESCE(v_lock_ok, 0) <> 1 THEN

      SET @erp_batch_blocked_message = 'Blocked: lock_move_wh_to_shopfloor lock is already held';

  END IF;


  IF COALESCE(v_lock_ok, 0) <> 1 THEN

      SET @erp_batch_blocked_message = 'Blocked: lock_move_wh_to_shopfloor lock is already held';

  END IF;

  IF v_lock_ok = 1 THEN
    OPEN cur;

    read_loop: LOOP
      FETCH cur INTO v_id, v_erp_id, v_need, v_where_to;
      IF v_done = 1 THEN
        LEAVE read_loop;
      END IF;

      SET v_parent_id = v_id;

      IF v_need <= 0 THEN
        ITERATE read_loop;
      END IF;

      START TRANSACTION;

      SELECT COALESCE(MAX(Quantity_in_warehouse), 0)
        INTO v_wh
        FROM `Main`
        WHERE ERP_ID = v_erp_id;

      IF v_wh >= v_need THEN
        UPDATE Transactions
        SET Order_wh = 'В комплектации',
            Status_warehouse = 'Комплектация',
            Status_transaction = 'В ожидании',
            updated_at = CURRENT_TIMESTAMP
        WHERE id = v_parent_id;

        UPDATE `Main`
        SET Quantity_in_warehouse = Quantity_in_warehouse - v_need,
            Quantity_in_kitting = COALESCE(Quantity_in_kitting, 0) + v_need,
            updated_at = CURRENT_TIMESTAMP
        WHERE ERP_ID = v_erp_id;

      ELSEIF v_wh > 0 THEN
        INSERT INTO Transactions (
          ERP_ID, linked_transaction, type, where_from, where_to,
          Quantity_of_parts_total, Quantity_change, Status_transaction,
          Project, Target_assembly, Supplied_component_number, Component_revision, Component_name,
          Quantity_in_target_assembly, Quantity_of_target_assemblies, Components_quantity_in_assembly,
          Component_type, For_supplied_as_assembly_components_provided_by_supplier, Part_material,
          Producer, Catalogue_number, Producer_article, Distributer, Distributer_article,
          MBOM_type, Mass_kg, Unit_of_measure, Height, Width, Length,
          Advanced_group, Address,
          Document_no, Zakaz_no, Date_needed, Date_expected, Cost_total_rub,
          Supplier, Location, Source, Initial_doc_no,
          Order_purch, Order_wh, Order_prod, Order_OTK, Status_warehouse,
          created_by, updated_by,
          created_at, updated_at
        )
        SELECT
          ERP_ID,
          CASE
            WHEN `linked_transaction` IS NULL OR TRIM(COALESCE(`linked_transaction`, '')) = '' THEN CAST(v_parent_id AS CHAR)
            ELSE CONCAT(TRIM(`linked_transaction`), '; ', v_parent_id)
          END,
          'move',
          'склад',
          v_where_to,
          v_wh,
          0,
          'В ожидании',
          Project, Target_assembly, Supplied_component_number, Component_revision, Component_name,
          Quantity_in_target_assembly, Quantity_of_target_assemblies, Components_quantity_in_assembly,
          Component_type, For_supplied_as_assembly_components_provided_by_supplier, Part_material,
          Producer, Catalogue_number, Producer_article, Distributer, Distributer_article,
          MBOM_type, Mass_kg, Unit_of_measure, Height, Width, Length,
          Advanced_group, Address,
          Document_no, Zakaz_no, Date_needed, Date_expected, Cost_total_rub,
          Supplier, Location, Source, Initial_doc_no,
          Order_purch,
          'В комплектации',
          Order_prod,
          Order_OTK,
          'Комплектация',
          created_by, updated_by,
          CURRENT_TIMESTAMP,
          CURRENT_TIMESTAMP
        FROM Transactions
        WHERE id = v_parent_id;

        UPDATE `Main`
        SET Quantity_in_warehouse = Quantity_in_warehouse - v_wh,
            Quantity_in_kitting = COALESCE(Quantity_in_kitting, 0) + v_wh,
            updated_at = CURRENT_TIMESTAMP
        WHERE ERP_ID = v_erp_id;

        INSERT INTO Transactions (
          ERP_ID, linked_transaction, type, where_from, where_to,
          Quantity_of_parts_total, Quantity_change, Status_transaction,
          Project, Target_assembly, Supplied_component_number, Component_revision, Component_name,
          Quantity_in_target_assembly, Quantity_of_target_assemblies, Components_quantity_in_assembly,
          Component_type, For_supplied_as_assembly_components_provided_by_supplier, Part_material,
          Producer, Catalogue_number, Producer_article, Distributer, Distributer_article,
          MBOM_type, Mass_kg, Unit_of_measure, Height, Width, Length,
          Advanced_group, Address,
          Document_no, Zakaz_no, Date_needed, Date_expected, Cost_total_rub,
          Supplier, Location, Source, Initial_doc_no,
          Order_purch, Order_wh, Order_prod, Order_OTK, Status_warehouse,
          created_by, updated_by,
          created_at, updated_at
        )
        SELECT
          ERP_ID,
          CASE
            WHEN `linked_transaction` IS NULL OR TRIM(COALESCE(`linked_transaction`, '')) = '' THEN CAST(v_parent_id AS CHAR)
            ELSE CONCAT(TRIM(`linked_transaction`), '; ', v_parent_id)
          END,
          'move',
          'склад',
          v_where_to,
          v_need - v_wh,
          0,
          'В ожидании',
          Project, Target_assembly, Supplied_component_number, Component_revision, Component_name,
          Quantity_in_target_assembly, Quantity_of_target_assemblies, Components_quantity_in_assembly,
          Component_type, For_supplied_as_assembly_components_provided_by_supplier, Part_material,
          Producer, Catalogue_number, Producer_article, Distributer, Distributer_article,
          MBOM_type, Mass_kg, Unit_of_measure, Height, Width, Length,
          Advanced_group, Address,
          Document_no, Zakaz_no, Date_needed, Date_expected, Cost_total_rub,
          Supplier, Location, Source, Initial_doc_no,
          Order_purch,
          NULL,
          Order_prod,
          Order_OTK,
          'Дефицит склада',
          created_by, updated_by,
          CURRENT_TIMESTAMP,
          CURRENT_TIMESTAMP
        FROM Transactions
        WHERE id = v_parent_id;

        UPDATE Transactions
        SET Status_transaction = 'Заменено',
            linked_transaction   = CASE
                WHEN `linked_transaction` IS NULL OR TRIM(COALESCE(`linked_transaction`, '')) = '' THEN CAST(id AS CHAR)
                ELSE CONCAT(TRIM(`linked_transaction`), '; ', id)
            END,
            updated_at = CURRENT_TIMESTAMP
        WHERE id = v_parent_id;

      ELSE
        UPDATE Transactions
        SET Status_warehouse = 'Дефицит склада',
            Status_transaction = 'В ожидании',
            updated_by = CASE
                           WHEN updated_by IS NULL OR TRIM(COALESCE(updated_by, '')) = '' THEN 'move_wh_to_shopfloor'
                           ELSE CONCAT(updated_by, '; ', 'move_wh_to_shopfloor')
                         END,
            updated_at = CURRENT_TIMESTAMP
        WHERE id = v_parent_id;
      END IF;

      COMMIT;
    END LOOP;

    CLOSE cur;

    START TRANSACTION;

    DROP TEMPORARY TABLE IF EXISTS tmp_ch_ids;
    CREATE TEMPORARY TABLE tmp_ch_ids (
      id INT UNSIGNED NOT NULL PRIMARY KEY
    );

    INSERT INTO tmp_ch_ids (id)
    SELECT t.id
    FROM `Transactions` t
    WHERE t.type = 'change'
      AND t.Order_purch = 'Ожидание закупки'
      AND (t.Status_transaction IS NULL OR t.Status_transaction = 'В ожидании')
      AND t.Status_warehouse IN ('Новая', 'Дефицит закупки')
      AND EXISTS (
          SELECT 1
          FROM `Transactions` t2
          WHERE t2.type = 'change'
            AND t2.Order_purch = 'Ожидание закупки'
            AND (t2.Status_transaction IS NULL OR t2.Status_transaction = 'В ожидании')
            AND t2.Status_warehouse IN ('Новая', 'Дефицит закупки')
            AND t2.ERP_ID = t.ERP_ID
            AND t2.Advanced_group <=> t.Advanced_group
            AND t2.id <> t.id
      );

    DROP TEMPORARY TABLE IF EXISTS tmp_ch_merge_queue;
    CREATE TEMPORARY TABLE tmp_ch_merge_queue (
      qid INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
      ERP_ID VARCHAR(255) NOT NULL,
      ag_key TEXT NOT NULL,
      sum_qty_change BIGINT NOT NULL,
      merge_source VARCHAR(255)
    );

    INSERT INTO tmp_ch_merge_queue (ERP_ID, ag_key, sum_qty_change, merge_source)
    SELECT
      t.ERP_ID,
      COALESCE(t.Advanced_group, '') AS ag_key,
      SUM(COALESCE(t.Quantity_change, 0)),
      CASE
        WHEN COUNT(DISTINCT t.`Source`) > 1 THEN 'Разные'
        ELSE MIN(t.`Source`)
      END
    FROM `Transactions` t
    JOIN tmp_ch_ids x ON x.id = t.id
    GROUP BY t.ERP_ID, COALESCE(t.Advanced_group, '')
    HAVING SUM(COALESCE(t.Quantity_change, 0)) > 0;

    merge_ch_loop: LOOP
      SELECT COUNT(*) INTO v_merge_left FROM tmp_ch_merge_queue;
      IF v_merge_left = 0 THEN
        LEAVE merge_ch_loop;
      END IF;

      SELECT MIN(qid) INTO v_qid FROM tmp_ch_merge_queue;

      SELECT ERP_ID, ag_key, sum_qty_change, merge_source
      INTO v_m_erp, v_m_ag_key, v_m_sum, v_m_src
      FROM tmp_ch_merge_queue
      WHERE qid = v_qid;

      INSERT INTO `Transactions` (
        ERP_ID, linked_transaction, created_at, updated_at, created_by, updated_by,
        type, where_from, where_to,
        Quantity_of_parts_total, Quantity_change, Status_transaction,
        Project, Target_assembly, Supplied_component_number, Component_revision, Component_name,
        Quantity_in_target_assembly, Quantity_of_target_assemblies, Components_quantity_in_assembly,
        Component_type, For_supplied_as_assembly_components_provided_by_supplier, Part_material,
        Producer, Catalogue_number, Producer_article, Distributer, Distributer_article,
        MBOM_type, Mass_kg, Unit_of_measure, Height, Width, Length,
        Advanced_group, Address,
        Document_no, Zakaz_no, Date_needed, Date_expected, Cost_total_rub,
        Supplier, Location, Source, Initial_doc_no,
        Order_purch, Order_wh, Order_prod, Order_OTK, Status_warehouse
      )
      SELECT
        v_m_erp,
        NULL,
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP,
        'move_wh_to_shopfloor',
        'move_wh_to_shopfloor',
        'change',
        'внешний',
        'склад',
        0,
        v_m_sum,
        'В ожидании',
        fld.`Project`,
        fld.`Target_assembly`,
        fld.`Supplied_component_number`,
        fld.`Component_revision`,
        fld.`Component_name`,
        fld.`Quantity_in_target_assembly`,
        fld.`Quantity_of_target_assemblies`,
        fld.`Components_quantity_in_assembly`,
        fld.`Component_type`,
        fld.`For_supplied_as_assembly_components_provided_by_supplier`,
        fld.`Part_material`,
        fld.`Producer`,
        fld.`Catalogue_number`,
        fld.`Producer_article`,
        fld.`Distributer`,
        fld.`Distributer_article`,
        fld.`MBOM_type`,
        fld.`Mass_kg`,
        fld.`Unit_of_measure`,
        fld.`Height`,
        fld.`Width`,
        fld.`Length`,
        NULLIF(v_m_ag_key, ''),
        fld.`Address`,
        fld.`Document_no`,
        fld.`Zakaz_no`,
        fld.`Date_needed`,
        fld.`Date_expected`,
        fld.`Cost_total_rub`,
        fld.`Supplier`,
        fld.`Location`,
        v_m_src,
        fld.`Initial_doc_no`,
        'Ожидание закупки',
        NULL,
        NULL,
        NULL,
        'Новая'
      FROM (
          SELECT
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
              MIN(t.`Document_no`) AS `Document_no`,
              MIN(t.`Zakaz_no`) AS `Zakaz_no`,
              MIN(t.`Date_needed`) AS `Date_needed`,
              MIN(t.`Date_expected`) AS `Date_expected`,
              MIN(t.`Cost_total_rub`) AS `Cost_total_rub`,
              MIN(t.`Supplier`) AS `Supplier`,
              MIN(t.`Location`) AS `Location`,
              MIN(t.`Initial_doc_no`) AS `Initial_doc_no`
          FROM `Transactions` t
          INNER JOIN `tmp_ch_ids` xi ON xi.`id` = t.`id`
          WHERE t.`ERP_ID` = v_m_erp
            AND COALESCE(t.`Advanced_group`, '') = v_m_ag_key
      ) fld;

      SET v_m_new_id = LAST_INSERT_ID();

      UPDATE `Transactions`
         SET linked_transaction   = CASE
             WHEN `linked_transaction` IS NULL OR TRIM(COALESCE(`linked_transaction`, '')) = '' THEN CAST(v_m_new_id AS CHAR)
             ELSE CONCAT(TRIM(`linked_transaction`), '; ', v_m_new_id)
         END
       WHERE id = v_m_new_id;

      UPDATE `Transactions` t
      INNER JOIN tmp_ch_ids xi ON xi.id = t.id
         SET t.linked_transaction   = CASE
             WHEN t.`linked_transaction` IS NULL OR TRIM(COALESCE(t.`linked_transaction`, '')) = '' THEN CAST(v_m_new_id AS CHAR)
             ELSE CONCAT(TRIM(t.`linked_transaction`), '; ', v_m_new_id)
         END,
             t.Status_transaction = 'Заменено',
             t.updated_by         = CASE
                                       WHEN t.updated_by IS NULL OR TRIM(COALESCE(t.updated_by, '')) = '' THEN 'move_wh_to_shopfloor'
                                       ELSE CONCAT(t.updated_by, '; ', 'move_wh_to_shopfloor')
                                    END,
             t.updated_at         = CURRENT_TIMESTAMP
       WHERE t.ERP_ID = v_m_erp
         AND COALESCE(t.Advanced_group, '') = v_m_ag_key;

      DELETE FROM tmp_ch_merge_queue WHERE qid = v_qid;
    END LOOP merge_ch_loop;

    DROP TEMPORARY TABLE IF EXISTS tmp_ch_merge_queue;
    DROP TEMPORARY TABLE IF EXISTS tmp_ch_ids;

    COMMIT;

    DO RELEASE_LOCK('lock_move_wh_to_shopfloor');
  END IF;
END$$

DELIMITER ;
