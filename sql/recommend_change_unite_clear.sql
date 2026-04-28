-- recommend_change_unite_clear: сброс Recommend_purchprod по id из tmp_ch_outside_unite_ids.
-- Вызывается из ch_outside_unite (и при необходимости из других сценариев с той же temp-таблицей).
-- tmp_ch_outside_unite_ids должна существовать до вызова (заполняется вызывающей логикой неттинга).

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

  UPDATE `Transactions` t
  INNER JOIN `tmp_ch_outside_unite_ids` x ON x.id = t.id
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
    END;
END$$

DELIMITER ;
