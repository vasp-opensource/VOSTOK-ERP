-- recommend_change_new: список id в JSON, передаётся вызывающей процедурой (см. recommend_change_purchprod.sql).
-- Параметр: p_row_ids — JSON-массив id, например CAST('[1,2,3]' AS JSON) или JSON_ARRAY(10, 20).
-- Рекомендация назначается по таблице recommend_rules.
-- Логика условий: WHERE начинает группу, AND добавляет условие в группу, OR начинает альтернативную группу.
-- Требуется: create_table_recommend_rules.sql; в Recommend_purchprod доступны значения «В закупку», «В собственное производство».
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
    DROP TEMPORARY TABLE IF EXISTS `tmp_recommend_change_new_ids`;
    CREATE TEMPORARY TABLE `tmp_recommend_change_new_ids` (
      id INT UNSIGNED NOT NULL PRIMARY KEY
    ) ENGINE=MEMORY;

    INSERT IGNORE INTO `tmp_recommend_change_new_ids` (id)
    SELECT j.id
    FROM JSON_TABLE(
      p_row_ids,
      '$[*]' COLUMNS (id INT UNSIGNED PATH '$')
    ) j
    WHERE j.id IS NOT NULL;

    DROP TEMPORARY TABLE IF EXISTS `tmp_recommend_change_new_rules`;
    CREATE TEMPORARY TABLE `tmp_recommend_change_new_rules` AS
    SELECT
      q.*,
      SUM(CASE WHEN q.`logic_operator` IN ('WHERE', 'OR') THEN 1 ELSE 0 END)
        OVER (PARTITION BY q.`rule_id` ORDER BY q.`priority`, q.`id`) AS condition_group
    FROM (
      SELECT
        r.`id`,
        r.`priority`,
        MIN(r.`priority`) OVER (PARTITION BY r.`rule_id`) AS rule_priority,
        r.`project`,
        r.`rule_id`,
        r.`recommend_purchprod`,
        r.`logic_operator`,
        r.`field_name`,
        r.`compare_operator`,
        r.`condition_value`
      FROM `recommend_rules` r
    ) q;
    ALTER TABLE `tmp_recommend_change_new_rules`
      ADD KEY `idx_tmp_rule` (`rule_id`, `condition_group`),
      ADD KEY `idx_tmp_priority` (`rule_priority`, `priority`, `id`);

    DROP TEMPORARY TABLE IF EXISTS `tmp_recommend_change_new_condition_matches`;
    CREATE TEMPORARY TABLE `tmp_recommend_change_new_condition_matches` AS
    SELECT
      q.tx_id,
      q.`rule_id`,
      q.`recommend_purchprod`,
      q.`rule_priority`,
      q.`priority`,
      q.rule_row_id,
      q.`condition_group`,
      CASE
        WHEN q.`field_name` = 'ANY'
          OR q.`condition_value` = 'ANY'
          THEN 1
        WHEN q.`compare_operator` = '='
          THEN TRIM(COALESCE(q.field_value, '')) COLLATE utf8mb4_unicode_ci
               = TRIM(q.`condition_value`) COLLATE utf8mb4_unicode_ci
        WHEN q.`compare_operator` = '<>'
          THEN TRIM(COALESCE(q.field_value, '')) COLLATE utf8mb4_unicode_ci
               <> TRIM(q.`condition_value`) COLLATE utf8mb4_unicode_ci
        WHEN q.`compare_operator` = 'like'
          THEN TRIM(COALESCE(q.field_value, '')) COLLATE utf8mb4_unicode_ci
               LIKE CONCAT('%', TRIM(q.`condition_value`), '%') COLLATE utf8mb4_unicode_ci
        WHEN q.`compare_operator` = 'not like'
          THEN TRIM(COALESCE(q.field_value, '')) COLLATE utf8mb4_unicode_ci
               NOT LIKE CONCAT('%', TRIM(q.`condition_value`), '%') COLLATE utf8mb4_unicode_ci
        WHEN q.`compare_operator` = '>'
          THEN CAST(COALESCE(q.field_value, '0') AS DECIMAL(30,10))
               > CAST(q.`condition_value` AS DECIMAL(30,10))
        WHEN q.`compare_operator` = '<'
          THEN CAST(COALESCE(q.field_value, '0') AS DECIMAL(30,10))
               < CAST(q.`condition_value` AS DECIMAL(30,10))
        WHEN q.`compare_operator` = '>='
          THEN CAST(COALESCE(q.field_value, '0') AS DECIMAL(30,10))
               >= CAST(q.`condition_value` AS DECIMAL(30,10))
        WHEN q.`compare_operator` = '<='
          THEN CAST(COALESCE(q.field_value, '0') AS DECIMAL(30,10))
               <= CAST(q.`condition_value` AS DECIMAL(30,10))
        ELSE 0
      END AS condition_ok
    FROM (
      SELECT
        t.id AS tx_id,
        rr.`rule_id`,
        rr.`recommend_purchprod`,
        rr.`rule_priority`,
        rr.`priority`,
        rr.`id` AS rule_row_id,
        rr.`condition_group`,
        rr.`field_name`,
        rr.`compare_operator`,
        rr.`condition_value`,
        CASE rr.`field_name`
          WHEN 'ANY' THEN 'ANY' COLLATE utf8mb4_unicode_ci
          WHEN 'ERP_ID' THEN CAST(t.`ERP_ID` AS CHAR CHARACTER SET utf8mb4) COLLATE utf8mb4_unicode_ci
          WHEN 'Project' THEN CAST(t.`Project` AS CHAR CHARACTER SET utf8mb4) COLLATE utf8mb4_unicode_ci
          WHEN 'Supplied_component_number' THEN CAST(t.`Supplied_component_number` AS CHAR CHARACTER SET utf8mb4) COLLATE utf8mb4_unicode_ci
          WHEN 'Component_revision' THEN CAST(t.`Component_revision` AS CHAR CHARACTER SET utf8mb4) COLLATE utf8mb4_unicode_ci
          WHEN 'Component_name' THEN CAST(t.`Component_name` AS CHAR CHARACTER SET utf8mb4) COLLATE utf8mb4_unicode_ci
          WHEN 'Component_type' THEN CAST(t.`Component_type` AS CHAR CHARACTER SET utf8mb4) COLLATE utf8mb4_unicode_ci
          WHEN 'MBOM_type' THEN CAST(t.`MBOM_type` AS CHAR CHARACTER SET utf8mb4) COLLATE utf8mb4_unicode_ci
        END AS field_value
      FROM `Transactions` t
      INNER JOIN `tmp_recommend_change_new_ids` i ON i.id = t.id
      INNER JOIN `tmp_recommend_change_new_rules` rr
        ON rr.`project` COLLATE utf8mb4_unicode_ci = 'ANY' COLLATE utf8mb4_unicode_ci
        OR FIND_IN_SET(
             TRIM(COALESCE(CAST(t.`Project` AS CHAR CHARACTER SET utf8mb4), '')) COLLATE utf8mb4_unicode_ci,
             REPLACE(CAST(rr.`project` AS CHAR CHARACTER SET utf8mb4), ', ', ',') COLLATE utf8mb4_unicode_ci
           ) > 0
    ) q;
    ALTER TABLE `tmp_recommend_change_new_condition_matches`
      ADD KEY `idx_tmp_condition_group` (`tx_id`, `rule_id`, `condition_group`),
      ADD KEY `idx_tmp_condition_priority` (`tx_id`, `rule_priority`, `priority`, `rule_row_id`);

    DROP TEMPORARY TABLE IF EXISTS `tmp_recommend_change_new_rule_matches`;
    CREATE TEMPORARY TABLE `tmp_recommend_change_new_rule_matches` AS
    SELECT
      cm.tx_id,
      cm.`rule_id`,
      cm.`recommend_purchprod`,
      MIN(cm.`rule_priority`) AS rule_priority,
      MIN(cm.`priority`) AS first_condition_priority,
      MIN(cm.`rule_row_id`) AS first_rule_row_id
    FROM `tmp_recommend_change_new_condition_matches` cm
    GROUP BY cm.tx_id, cm.`rule_id`, cm.`recommend_purchprod`, cm.`condition_group`
    HAVING MIN(cm.condition_ok) = 1;
    ALTER TABLE `tmp_recommend_change_new_rule_matches`
      ADD KEY `idx_tmp_match_priority` (`tx_id`, `rule_priority`, `first_condition_priority`, `first_rule_row_id`);

    DROP TEMPORARY TABLE IF EXISTS `tmp_recommend_change_new_selected`;
    CREATE TEMPORARY TABLE `tmp_recommend_change_new_selected` AS
    SELECT
      q.tx_id,
      q.`recommend_purchprod`
    FROM (
      SELECT
        m.*,
        ROW_NUMBER() OVER (
          PARTITION BY m.tx_id
          ORDER BY m.rule_priority, m.first_condition_priority, m.first_rule_row_id
        ) AS rn
      FROM `tmp_recommend_change_new_rule_matches` m
    ) q
    WHERE q.rn = 1;
    ALTER TABLE `tmp_recommend_change_new_selected` ADD PRIMARY KEY (`tx_id`);

    UPDATE `Transactions` t
    INNER JOIN `tmp_recommend_change_new_selected` s ON s.tx_id = t.id
    SET
      t.`Recommend_purchprod` = s.`recommend_purchprod`,
      t.`updated_at`   = NOW(),
      t.`updated_by`  = CASE
        WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'recommend_change_new'
        WHEN FIND_IN_SET(
               'recommend_change_new' COLLATE utf8mb4_unicode_ci,
               REPLACE(t.`updated_by` COLLATE utf8mb4_unicode_ci, '; ', ',')
             ) > 0 THEN t.`updated_by`
        ELSE LEFT(CONCAT(TRIM(TRAILING ';' FROM TRIM(t.`updated_by`)), '; ', 'recommend_change_new'), v_updated_by_max)
      END
    WHERE NOT (
      CAST(t.`Recommend_purchprod` AS CHAR CHARACTER SET utf8mb4) COLLATE utf8mb4_unicode_ci
      <=> CAST(s.`recommend_purchprod` AS CHAR CHARACTER SET utf8mb4) COLLATE utf8mb4_unicode_ci
    );

    DROP TEMPORARY TABLE IF EXISTS `tmp_recommend_change_new_selected`;
    DROP TEMPORARY TABLE IF EXISTS `tmp_recommend_change_new_rule_matches`;
    DROP TEMPORARY TABLE IF EXISTS `tmp_recommend_change_new_condition_matches`;
    DROP TEMPORARY TABLE IF EXISTS `tmp_recommend_change_new_rules`;
    DROP TEMPORARY TABLE IF EXISTS `tmp_recommend_change_new_ids`;
  END IF;
END$$

DELIMITER ;
