-- recommend_change_unite_clear: сброс Recommend_purchprod.
-- Вход: tmp_recommend_change_unite_clear_ids(id) с текущими обрабатываемыми строками.
-- Процедура сама находит смежные change-строки по Supplied_component_number
-- в Status_warehouse («Новая», «В закупке», «В изготовлении»).

DELIMITER $$

DROP PROCEDURE IF EXISTS `recommend_change_unite_clear`$$

CREATE PROCEDURE `recommend_change_unite_clear`(
  IN p_proc_name VARCHAR(64)
)
BEGIN
  DECLARE v_updated_by_max INT DEFAULT 255;

  SELECT COALESCE(c.CHARACTER_MAXIMUM_LENGTH, 255)
    INTO v_updated_by_max
  FROM information_schema.COLUMNS c
  WHERE c.TABLE_SCHEMA = DATABASE()
    AND c.TABLE_NAME = 'Transactions'
    AND c.COLUMN_NAME = 'updated_by'
  LIMIT 1;

  DROP TEMPORARY TABLE IF EXISTS `tmp_recommend_change_unite_clear_scope`;
  CREATE TEMPORARY TABLE `tmp_recommend_change_unite_clear_scope` (
    `pnum` VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
    KEY `idx_scope_pnum` (`pnum`)
  ) AS
  SELECT DISTINCT
    CAST(LEFT(COALESCE(t.`Supplied_component_number`, ''), 255) AS CHAR CHARACTER SET utf8mb4) COLLATE utf8mb4_unicode_ci AS `pnum`
  FROM `Transactions` t
  INNER JOIN `tmp_recommend_change_unite_clear_ids` seed ON seed.id = t.id;

  UPDATE `Transactions` t
  LEFT JOIN `tmp_recommend_change_unite_clear_ids` seed ON seed.id = t.id
  LEFT JOIN `tmp_recommend_change_unite_clear_scope` s_part
    ON s_part.`pnum` COLLATE utf8mb4_unicode_ci = LEFT(COALESCE(t.`Supplied_component_number`, ''), 255) COLLATE utf8mb4_unicode_ci
  SET
    t.`Recommend_purchprod` = NULL,
    t.`updated_at`          = NOW(),
    t.`updated_by`          = CASE
      WHEN t.`updated_by` IS NULL
        OR TRIM(COALESCE(t.`updated_by` COLLATE utf8mb4_unicode_ci, '' COLLATE utf8mb4_unicode_ci)) = '' COLLATE utf8mb4_unicode_ci
        THEN CAST(p_proc_name AS CHAR CHARACTER SET utf8mb4) COLLATE utf8mb4_unicode_ci
      WHEN FIND_IN_SET(
             CAST(p_proc_name AS CHAR CHARACTER SET utf8mb4) COLLATE utf8mb4_unicode_ci,
             REPLACE(
               t.`updated_by` COLLATE utf8mb4_unicode_ci,
               '; ' COLLATE utf8mb4_unicode_ci,
               ',' COLLATE utf8mb4_unicode_ci
             )
           ) > 0 THEN t.`updated_by`
      ELSE LEFT(CONCAT(
             t.`updated_by` COLLATE utf8mb4_unicode_ci,
             '; ' COLLATE utf8mb4_unicode_ci,
             CAST(p_proc_name AS CHAR CHARACTER SET utf8mb4) COLLATE utf8mb4_unicode_ci
           ), v_updated_by_max)
    END
  WHERE
    seed.id IS NOT NULL
    OR (
      t.`type` = 'change'
      AND t.`Status_transaction` = 'В ожидании'
      AND t.`Status_warehouse` IN ('Новая', 'В закупке', 'В изготовлении')
      AND s_part.`pnum` IS NOT NULL
    );

  DROP TEMPORARY TABLE IF EXISTS `tmp_recommend_change_unite_clear_scope`;
END$$

DELIMITER ;
