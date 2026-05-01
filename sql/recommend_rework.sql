-- recommend_rework: детализация рекомендации по доработке запасов.
-- Параметры:
--   p_transaction_id — текущая change-строка старой ревизии;
--   p_source         — источник запаса: warehouse, kitting, prod.

DELIMITER $$

DROP PROCEDURE IF EXISTS `recommend_rework`$$

CREATE PROCEDURE `recommend_rework`(
  IN p_transaction_id INT UNSIGNED,
  IN p_source VARCHAR(32)
)
BEGIN
  DECLARE v_pnum VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL;
  DECLARE v_updated_by_max INT DEFAULT 2000;

  SELECT COALESCE(c.CHARACTER_MAXIMUM_LENGTH, 2000)
    INTO v_updated_by_max
  FROM information_schema.COLUMNS c
  WHERE c.TABLE_SCHEMA = DATABASE()
    AND c.TABLE_NAME = 'Transactions'
    AND c.COLUMN_NAME = 'updated_by'
  LIMIT 1;

  SELECT CAST(LEFT(COALESCE(t.`Supplied_component_number`, ''), 255) AS CHAR CHARACTER SET utf8mb4) COLLATE utf8mb4_unicode_ci
    INTO v_pnum
  FROM `Transactions` t
  WHERE t.id = p_transaction_id
  LIMIT 1;

  IF p_source IN ('warehouse', 'kitting', 'prod') THEN
    UPDATE `Transactions` t
    SET
      t.`Recommend_wh` = 'забраковать ИЛИ доработать запас ИЛИ отменить',
      t.`updated_at` = NOW(),
      t.`updated_by` = CASE
        WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'recommend_rework'
        ELSE LEFT(CONCAT(t.`updated_by`, '; ', 'recommend_rework'), v_updated_by_max)
      END
    WHERE t.id = p_transaction_id;
  END IF;

  IF p_source = 'kitting' THEN
    UPDATE `Transactions` t
    SET
      t.`Recommend_wh` = 'вернуть на склад',
      t.`updated_at` = NOW(),
      t.`updated_by` = CASE
        WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'recommend_rework'
        ELSE LEFT(CONCAT(t.`updated_by`, '; ', 'recommend_rework'), v_updated_by_max)
      END
    WHERE t.`type` = 'move'
      AND t.`Status_transaction` = 'В ожидании'
      AND t.`Status_warehouse` = 'Комплектация'
      AND CAST(LEFT(COALESCE(t.`Supplied_component_number`, ''), 255) AS CHAR CHARACTER SET utf8mb4) COLLATE utf8mb4_unicode_ci = v_pnum COLLATE utf8mb4_unicode_ci;
  END IF;

  IF p_source = 'prod' THEN
    UPDATE `Transactions` t
    SET
      t.`Recommend_wh` = 'вернуть на склад',
      t.`updated_at` = NOW(),
      t.`updated_by` = CASE
        WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'recommend_rework'
        ELSE LEFT(CONCAT(t.`updated_by`, '; ', 'recommend_rework'), v_updated_by_max)
      END
    WHERE t.`type` = 'move'
      AND t.`Status_transaction` = 'В ожидании'
      AND t.`Status_warehouse` IN ('Комплектация', 'Сборка', 'Упаковка')
      AND CAST(LEFT(COALESCE(t.`Supplied_component_number`, ''), 255) AS CHAR CHARACTER SET utf8mb4) COLLATE utf8mb4_unicode_ci = v_pnum COLLATE utf8mb4_unicode_ci;
  END IF;
END$$

DELIMITER ;
