-- prework_default_location: назначает Main.cell_id по правилам из location_rules.
-- Обрабатываются Transactions со Status_transaction = 'В ожидании' и пустым Main.cell_id.
-- Логика правил аналогична recommend_change_new:
-- WHERE начинает группу, AND дополняет, OR открывает альтернативную группу.

DROP PROCEDURE IF EXISTS `prework_default_location`;

DELIMITER $$

CREATE PROCEDURE `prework_default_location`()
BEGIN
  DECLARE v_lock_ok INT DEFAULT 0;
  DECLARE v_updated_by_max INT DEFAULT 255;

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    IF v_lock_ok = 1 THEN
      DO RELEASE_LOCK('lock_prework_default_location');
    END IF;
    RESIGNAL;
  END;

  SELECT COALESCE(c.CHARACTER_MAXIMUM_LENGTH, 255)
    INTO v_updated_by_max
  FROM information_schema.COLUMNS c
  WHERE c.TABLE_SCHEMA = DATABASE()
    AND c.TABLE_NAME = 'Main'
    AND c.COLUMN_NAME = 'updated_by'
  LIMIT 1;

  SELECT GET_LOCK('lock_prework_default_location', 0) INTO v_lock_ok;

  IF COALESCE(v_lock_ok, 0) <> 1 THEN
    SET @erp_batch_blocked_message = 'Blocked: lock_prework_default_location lock is already held';
  ELSE
    DROP TEMPORARY TABLE IF EXISTS `tmp_prework_default_location_candidates`;
    CREATE TEMPORARY TABLE `tmp_prework_default_location_candidates` (
      tx_id INT UNSIGNED NOT NULL PRIMARY KEY,
      ERP_ID VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL
    ) ENGINE=MEMORY;

    INSERT IGNORE INTO `tmp_prework_default_location_candidates` (tx_id, ERP_ID)
    SELECT
      t.`id`,
      CAST(t.`ERP_ID` AS CHAR CHARACTER SET utf8mb4) COLLATE utf8mb4_unicode_ci
    FROM `Transactions` t
    INNER JOIN `Main` m
      ON m.`ERP_ID` COLLATE utf8mb4_unicode_ci = t.`ERP_ID` COLLATE utf8mb4_unicode_ci
    WHERE t.`Status_transaction` = 'В ожидании'
      AND t.`ERP_ID` IS NOT NULL
      AND m.`cell_id` IS NULL;

    DROP TEMPORARY TABLE IF EXISTS `tmp_prework_default_location_rules`;
    CREATE TEMPORARY TABLE `tmp_prework_default_location_rules` AS
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
        r.`default_address`,
        r.`logic_operator`,
        r.`field_name`,
        r.`compare_operator`,
        r.`condition_value`
      FROM `location_rules` r
      WHERE r.`default_address` IS NOT NULL
    ) q;
    ALTER TABLE `tmp_prework_default_location_rules`
      ADD KEY `idx_tmp_rule` (`rule_id`, `condition_group`),
      ADD KEY `idx_tmp_priority` (`rule_priority`, `priority`, `id`);

    DROP TEMPORARY TABLE IF EXISTS `tmp_prework_default_location_condition_matches`;
    CREATE TEMPORARY TABLE `tmp_prework_default_location_condition_matches` AS
    SELECT
      q.tx_id,
      q.ERP_ID,
      q.`rule_id`,
      q.`default_address`,
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
        t.`id` AS tx_id,
        CAST(t.`ERP_ID` AS CHAR CHARACTER SET utf8mb4) COLLATE utf8mb4_unicode_ci AS ERP_ID,
        rr.`rule_id`,
        rr.`default_address`,
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
          WHEN 'Status_transaction' THEN CAST(t.`Status_transaction` AS CHAR CHARACTER SET utf8mb4) COLLATE utf8mb4_unicode_ci
          WHEN 'Status_warehouse' THEN CAST(t.`Status_warehouse` AS CHAR CHARACTER SET utf8mb4) COLLATE utf8mb4_unicode_ci
          WHEN 'Order_prod' THEN CAST(t.`Order_prod` AS CHAR CHARACTER SET utf8mb4) COLLATE utf8mb4_unicode_ci
          WHEN 'Recommend_wh' THEN CAST(t.`Recommend_wh` AS CHAR CHARACTER SET utf8mb4) COLLATE utf8mb4_unicode_ci
          WHEN 'Quantity_change' THEN CAST(t.`Quantity_change` AS CHAR CHARACTER SET utf8mb4) COLLATE utf8mb4_unicode_ci
          WHEN 'Quantity_of_parts_total' THEN CAST(t.`Quantity_of_parts_total` AS CHAR CHARACTER SET utf8mb4) COLLATE utf8mb4_unicode_ci
          ELSE NULL
        END AS field_value
      FROM `Transactions` t
      INNER JOIN `tmp_prework_default_location_candidates` i ON i.tx_id = t.`id`
      INNER JOIN `tmp_prework_default_location_rules` rr
        ON TRIM(CAST(rr.`project` AS CHAR CHARACTER SET utf8mb4)) COLLATE utf8mb4_unicode_ci = 'ANY' COLLATE utf8mb4_unicode_ci
        OR (
          UPPER(TRIM(CAST(rr.`project` AS CHAR CHARACTER SET utf8mb4))) COLLATE utf8mb4_unicode_ci
            LIKE 'ANY BUT %' COLLATE utf8mb4_unicode_ci
          AND FIND_IN_SET(
                TRIM(COALESCE(CAST(t.`Project` AS CHAR CHARACTER SET utf8mb4), '')) COLLATE utf8mb4_unicode_ci,
                REPLACE(
                  TRIM(SUBSTRING(TRIM(CAST(rr.`project` AS CHAR CHARACTER SET utf8mb4)), 8)),
                  ', ',
                  ','
                ) COLLATE utf8mb4_unicode_ci
              ) = 0
        )
        OR FIND_IN_SET(
             TRIM(COALESCE(CAST(t.`Project` AS CHAR CHARACTER SET utf8mb4), '')) COLLATE utf8mb4_unicode_ci,
             REPLACE(CAST(rr.`project` AS CHAR CHARACTER SET utf8mb4), ', ', ',') COLLATE utf8mb4_unicode_ci
           ) > 0
    ) q;
    ALTER TABLE `tmp_prework_default_location_condition_matches`
      ADD KEY `idx_tmp_condition_group` (`tx_id`, `rule_id`, `condition_group`),
      ADD KEY `idx_tmp_condition_priority` (`tx_id`, `rule_priority`, `priority`, `rule_row_id`);

    DROP TEMPORARY TABLE IF EXISTS `tmp_prework_default_location_rule_matches`;
    CREATE TEMPORARY TABLE `tmp_prework_default_location_rule_matches` AS
    SELECT
      cm.tx_id,
      cm.ERP_ID,
      cm.`rule_id`,
      cm.`default_address`,
      MIN(cm.`rule_priority`) AS rule_priority,
      MIN(cm.`priority`) AS first_condition_priority,
      MIN(cm.`rule_row_id`) AS first_rule_row_id
    FROM `tmp_prework_default_location_condition_matches` cm
    GROUP BY cm.tx_id, cm.ERP_ID, cm.`rule_id`, cm.`default_address`, cm.`condition_group`
    HAVING MIN(cm.condition_ok) = 1;
    ALTER TABLE `tmp_prework_default_location_rule_matches`
      ADD KEY `idx_tmp_match_priority` (`tx_id`, `rule_priority`, `first_condition_priority`, `first_rule_row_id`);

    DROP TEMPORARY TABLE IF EXISTS `tmp_prework_default_location_selected_tx`;
    CREATE TEMPORARY TABLE `tmp_prework_default_location_selected_tx` AS
    SELECT
      q.tx_id,
      q.ERP_ID,
      q.`default_address`
    FROM (
      SELECT
        m.*,
        ROW_NUMBER() OVER (
          PARTITION BY m.tx_id
          ORDER BY m.rule_priority, m.first_condition_priority, m.first_rule_row_id
        ) AS rn
      FROM `tmp_prework_default_location_rule_matches` m
    ) q
    WHERE q.rn = 1;
    ALTER TABLE `tmp_prework_default_location_selected_tx`
      ADD KEY `idx_tmp_selected_erp` (`ERP_ID`);

    DROP TEMPORARY TABLE IF EXISTS `tmp_prework_default_location_selected_erp`;
    CREATE TEMPORARY TABLE `tmp_prework_default_location_selected_erp` AS
    SELECT
      q.ERP_ID,
      q.`default_address`
    FROM (
      SELECT
        s.*,
        ROW_NUMBER() OVER (
          PARTITION BY s.ERP_ID
          ORDER BY s.tx_id
        ) AS rn
      FROM `tmp_prework_default_location_selected_tx` s
      WHERE s.`default_address` IS NOT NULL
    ) q
    WHERE q.rn = 1;
    ALTER TABLE `tmp_prework_default_location_selected_erp`
      ADD PRIMARY KEY (`ERP_ID`);

    UPDATE `Main` m
    INNER JOIN `tmp_prework_default_location_selected_erp` s
      ON s.`ERP_ID` COLLATE utf8mb4_unicode_ci = m.`ERP_ID` COLLATE utf8mb4_unicode_ci
    SET
      m.`cell_id` = s.`default_address`,
      m.`updated_at` = NOW(),
      m.`updated_by` = CASE
        WHEN m.`updated_by` IS NULL OR TRIM(COALESCE(m.`updated_by`, '')) = '' THEN 'prework_default_location'
        WHEN FIND_IN_SET(
               'prework_default_location' COLLATE utf8mb4_unicode_ci,
               REPLACE(m.`updated_by` COLLATE utf8mb4_unicode_ci, '; ', ',')
             ) > 0 THEN m.`updated_by`
        ELSE LEFT(CONCAT(TRIM(TRAILING ';' FROM TRIM(m.`updated_by`)), '; ', 'prework_default_location'), v_updated_by_max)
      END
    WHERE m.`cell_id` IS NULL
      AND s.`default_address` IS NOT NULL;

    DROP TEMPORARY TABLE IF EXISTS `tmp_prework_default_location_selected_erp`;
    DROP TEMPORARY TABLE IF EXISTS `tmp_prework_default_location_selected_tx`;
    DROP TEMPORARY TABLE IF EXISTS `tmp_prework_default_location_rule_matches`;
    DROP TEMPORARY TABLE IF EXISTS `tmp_prework_default_location_condition_matches`;
    DROP TEMPORARY TABLE IF EXISTS `tmp_prework_default_location_rules`;
    DROP TEMPORARY TABLE IF EXISTS `tmp_prework_default_location_candidates`;

    DO RELEASE_LOCK('lock_prework_default_location');
  END IF;
END$$

DELIMITER ;
