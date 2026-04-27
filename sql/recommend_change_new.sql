-- recommend_change_new: список id в JSON, передаётся вызывающей процедурой (см. recommend_change_purchprod.sql).
-- Параметр: p_row_ids — JSON-массив id, например CAST('[1,2,3]' AS JSON) или JSON_ARRAY(10, 20).
-- Требуется: в Recommend_purchprod доступны значения «В закупку», «В собственное производство».
-- MySQL 8+ (JSON_TABLE).

DELIMITER $$

DROP PROCEDURE IF EXISTS `recommend_change_new`$$

CREATE PROCEDURE `recommend_change_new`(
  IN p_row_ids JSON
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

  IF p_row_ids IS NOT NULL
     AND JSON_TYPE(p_row_ids) = 'ARRAY'
     AND JSON_LENGTH(p_row_ids) > 0
  THEN
    UPDATE `Transactions` t
    INNER JOIN JSON_TABLE(
      p_row_ids,
      '$[*]' COLUMNS (id INT UNSIGNED PATH '$')
    ) j ON j.id = t.id
    SET
      t.`Recommend_purchprod` = CASE
        WHEN t.`Component_type` IN ('Покупное изделие', 'Стандартное изделие') THEN 'В закупку'
        WHEN t.`Component_type` IN ('Комплект', 'Комплекс', 'Сборочная единица') THEN 'В собственное производство'
      END,
      t.`updated_at`   = NOW(),
      t.`updated_by`  = CASE
        WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'recommend_change_new'
        WHEN FIND_IN_SET(
               'recommend_change_new' COLLATE utf8mb4_unicode_ci,
               REPLACE(t.`updated_by` COLLATE utf8mb4_unicode_ci, '; ', ',')
             ) > 0 THEN t.`updated_by`
        ELSE LEFT(CONCAT(t.`updated_by`, '; ', 'recommend_change_new'), v_updated_by_max)
      END
    WHERE
      t.`Component_type` IN (
        'Покупное изделие', 'Стандартное изделие',
        'Комплект', 'Комплекс', 'Сборочная единица'
      );
  END IF;
END$$

DELIMITER ;
