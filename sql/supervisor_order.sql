-- supervisor_order: обработка распоряжений супервизора склада по Order_sv.

DELIMITER $$

DROP PROCEDURE IF EXISTS `supervisor_order`$$

CREATE PROCEDURE `supervisor_order`()
BEGIN
  DECLARE done INT DEFAULT 0;
  DECLARE v_id INT UNSIGNED;
  DECLARE v_type VARCHAR(16);
  DECLARE v_order_sv VARCHAR(64);
  DECLARE v_recommend_wh TEXT;
  DECLARE v_quantity_ordered BIGINT;
  DECLARE v_qty_total BIGINT;
  DECLARE v_qty_change BIGINT;
  DECLARE v_replace_to TEXT;
  DECLARE v_updated_by_max INT DEFAULT 2000;

  DECLARE cur CURSOR FOR
    SELECT
      t.id, t.`type`, t.`Order_sv`, t.`Recommend_wh`,
      COALESCE(t.`Quantity_ordered`, 0),
      COALESCE(t.`Quantity_of_parts_total`, 0),
      COALESCE(t.`Quantity_change`, 0),
      t.`Replace_to`
    FROM `Transactions` t
    WHERE t.`type` IN ('change', 'move')
      AND t.`Status_transaction` = 'В ожидании'
      AND t.`Order_sv` IS NOT NULL
    ORDER BY t.id;

  DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;

  SELECT COALESCE(c.CHARACTER_MAXIMUM_LENGTH, 2000)
    INTO v_updated_by_max
  FROM information_schema.COLUMNS c
  WHERE c.TABLE_SCHEMA = DATABASE()
    AND c.TABLE_NAME = 'Transactions'
    AND c.COLUMN_NAME = 'updated_by'
  LIMIT 1;

  OPEN cur;
  read_loop: LOOP
    FETCH cur INTO v_id, v_type, v_order_sv, v_recommend_wh, v_quantity_ordered, v_qty_total, v_qty_change, v_replace_to;
    IF done = 1 THEN
      LEAVE read_loop;
    END IF;

    IF v_order_sv = 'разбить' AND v_quantity_ordered > 0 THEN
      IF v_type = 'move' AND v_quantity_ordered < v_qty_total THEN
        CALL `split`(v_id, v_quantity_ordered, NULL, NULL);
      ELSEIF v_type = 'change' AND v_quantity_ordered < ABS(v_qty_change) THEN
        CALL `split`(v_id, v_quantity_ordered, NULL, NULL);
      END IF;

      UPDATE `Transactions`
      SET `Order_sv` = NULL
      WHERE id = v_id;

    ELSEIF v_type = 'change'
       AND v_recommend_wh COLLATE utf8mb4_unicode_ci LIKE '%забраковать%' COLLATE utf8mb4_unicode_ci
       AND v_order_sv = 'забраковать'
       AND v_qty_change < 0 THEN
      CALL `brak`(v_id);

    ELSEIF v_type = 'change'
       AND v_recommend_wh COLLATE utf8mb4_unicode_ci LIKE '%отменить%' COLLATE utf8mb4_unicode_ci
       AND v_order_sv = 'отменить'
       AND v_qty_change < 0 THEN
      UPDATE `Transactions` t
      SET
        t.`Status_transaction` = 'Отменено',
        t.`Order_sv` = NULL,
        t.`updated_by` = CASE WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'supervisor_order' ELSE LEFT(CONCAT(t.`updated_by`, '; ', 'supervisor_order'), v_updated_by_max) END,
        t.`updated_at` = CURRENT_TIMESTAMP
      WHERE t.id = v_id;

    ELSEIF v_type = 'change'
       AND v_recommend_wh COLLATE utf8mb4_unicode_ci LIKE '%доработать запас%' COLLATE utf8mb4_unicode_ci
       AND v_order_sv = 'доработать запас'
       AND v_qty_change < 0 THEN
      CALL `rework`(v_id);

    ELSEIF v_type = 'move'
       AND v_order_sv = 'заменить со склада'
       AND v_replace_to IS NOT NULL
       AND TRIM(v_replace_to) <> '' THEN
      CALL `replace_wh`(v_id);

    ELSEIF v_type IN ('change', 'move')
       AND v_order_sv = 'заменить и восполнить'
       AND v_replace_to IS NOT NULL
       AND TRIM(v_replace_to) <> '' THEN
      CALL `replace_new`(v_id);
    END IF;
  END LOOP;
  CLOSE cur;
END$$

DELIMITER ;
