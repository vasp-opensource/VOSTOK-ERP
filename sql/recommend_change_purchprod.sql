-- recommend_change_purchprod: отбор + смена Recommend_purchprod, затем recommend_change_new(JSON id).
-- Зависимости: recommend_change_new.sql, MySQL 8+.
-- recommend_change_unite_clear — в отдельном файле recommend_change_unite_clear.sql.
-- Точка входа: recommend_call.sql.

DELIMITER $$

/* Удаление устаревшей обёртки */
DROP PROCEDURE IF EXISTS `recommendations_change_purchprod`$$

DROP PROCEDURE IF EXISTS `recommend_change_purchprod`$$

CREATE PROCEDURE `recommend_change_purchprod`()
BEGIN
  DECLARE v_ids JSON DEFAULT NULL;
  DECLARE v_updated_by_max INT DEFAULT 255;

  SELECT COALESCE(c.CHARACTER_MAXIMUM_LENGTH, 255)
    INTO v_updated_by_max
  FROM information_schema.COLUMNS c
  WHERE c.TABLE_SCHEMA = DATABASE()
    AND c.TABLE_NAME = 'Transactions'
    AND c.COLUMN_NAME = 'updated_by'
  LIMIT 1;

  DROP TEMPORARY TABLE IF EXISTS `tmp_recommend_purchprod_candidates`;
  CREATE TEMPORARY TABLE `tmp_recommend_purchprod_candidates` (
    id INT UNSIGNED NOT NULL PRIMARY KEY,
    `ERP_ID` VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
    `Supplied_component_number` TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL
  );

  INSERT INTO `tmp_recommend_purchprod_candidates` (id, `ERP_ID`, `Supplied_component_number`)
  SELECT
    t.id,
    CAST(t.`ERP_ID` AS CHAR CHARACTER SET utf8mb4) COLLATE utf8mb4_unicode_ci,
    CAST(t.`Supplied_component_number` AS CHAR CHARACTER SET utf8mb4) COLLATE utf8mb4_unicode_ci
  FROM `Transactions` t
  WHERE t.`type` = 'change'
    AND t.`Status_transaction` = 'В ожидании'
    AND t.`Status_warehouse` = 'Новая'
    AND t.`Recommend_purchprod` IS NULL;

  DROP TEMPORARY TABLE IF EXISTS `tmp_recommend_erp_scope`;
  CREATE TEMPORARY TABLE `tmp_recommend_erp_scope` (
    `ERP_ID` VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
    KEY `k_erp` (`ERP_ID`)
  ) AS
  SELECT DISTINCT `ERP_ID`
  FROM `tmp_recommend_purchprod_candidates`;

  DROP TEMPORARY TABLE IF EXISTS `tmp_recommend_part_scope`;
  CREATE TEMPORARY TABLE `tmp_recommend_part_scope` (
    `pnum` VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
    KEY `k_part` (`pnum`)
  ) AS
  SELECT DISTINCT LEFT(COALESCE(`Supplied_component_number`, ''), 255) AS `pnum`
  FROM `tmp_recommend_purchprod_candidates`;

  /* Агрегаты для исключения текущей строки: same = group_sum - own_qty_if_in_same_status */
  DROP TEMPORARY TABLE IF EXISTS `tmp_sum_erp_manuf`;
  CREATE TEMPORARY TABLE `tmp_sum_erp_manuf` AS
  SELECT
    CAST(t.`ERP_ID` AS CHAR CHARACTER SET utf8mb4) COLLATE utf8mb4_unicode_ci AS `ERP_ID`,
    SUM(COALESCE(t.`Quantity_change`, 0)) AS sum_qty
  FROM `Transactions` t
  WHERE t.`type` = 'change'
    AND t.`Status_warehouse` = 'В изготовлении'
  GROUP BY t.`ERP_ID`;
  ALTER TABLE `tmp_sum_erp_manuf` ADD KEY `k_erp` (`ERP_ID`);

  DROP TEMPORARY TABLE IF EXISTS `tmp_sum_erp_purch`;
  CREATE TEMPORARY TABLE `tmp_sum_erp_purch` AS
  SELECT
    CAST(t.`ERP_ID` AS CHAR CHARACTER SET utf8mb4) COLLATE utf8mb4_unicode_ci AS `ERP_ID`,
    SUM(COALESCE(t.`Quantity_change`, 0)) AS sum_qty
  FROM `Transactions` t
  WHERE t.`type` = 'change'
    AND t.`Status_warehouse` = 'В закупке'
  GROUP BY t.`ERP_ID`;
  ALTER TABLE `tmp_sum_erp_purch` ADD KEY `k_erp` (`ERP_ID`);

  DROP TEMPORARY TABLE IF EXISTS `tmp_sum_part_manuf`;
  CREATE TEMPORARY TABLE `tmp_sum_part_manuf` AS
  SELECT
    q.`pnum`,
    SUM(COALESCE(q.`Quantity_change`, 0)) AS sum_qty
  FROM (
    SELECT
      CAST(LEFT(COALESCE(t.`Supplied_component_number`, ''), 255) AS CHAR CHARACTER SET utf8mb4) COLLATE utf8mb4_unicode_ci AS `pnum`,
      t.`Quantity_change`
    FROM `Transactions` t
    WHERE t.`type` = 'change'
      AND t.`Status_warehouse` = 'В изготовлении'
  ) q
  GROUP BY q.`pnum`;
  ALTER TABLE `tmp_sum_part_manuf` ADD KEY `k_part` (`pnum`);

  DROP TEMPORARY TABLE IF EXISTS `tmp_sum_part_purch`;
  CREATE TEMPORARY TABLE `tmp_sum_part_purch` AS
  SELECT
    q.`pnum`,
    SUM(COALESCE(q.`Quantity_change`, 0)) AS sum_qty
  FROM (
    SELECT
      CAST(LEFT(COALESCE(t.`Supplied_component_number`, ''), 255) AS CHAR CHARACTER SET utf8mb4) COLLATE utf8mb4_unicode_ci AS `pnum`,
      t.`Quantity_change`
    FROM `Transactions` t
    WHERE t.`type` = 'change'
      AND t.`Status_warehouse` = 'В закупке'
  ) q
  GROUP BY q.`pnum`;
  ALTER TABLE `tmp_sum_part_purch` ADD KEY `k_part` (`pnum`);

  /* 1) same_erp_id_inManuf > 0 */
  UPDATE `Transactions` t
  INNER JOIN `tmp_recommend_erp_scope` s ON s.`ERP_ID` COLLATE utf8mb4_unicode_ci <=> t.`ERP_ID` COLLATE utf8mb4_unicode_ci
  LEFT JOIN `tmp_sum_erp_manuf` m ON m.`ERP_ID` COLLATE utf8mb4_unicode_ci <=> t.`ERP_ID` COLLATE utf8mb4_unicode_ci
  SET
    t.`Recommend_purchprod` = 'Уточнить кол-во в изготовлении',
    t.`updated_at`         = NOW(),
    t.`updated_by`         = CASE
      WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'recommend_change_purchprod'
      WHEN FIND_IN_SET(
             'recommend_change_purchprod' COLLATE utf8mb4_unicode_ci,
             REPLACE(t.`updated_by` COLLATE utf8mb4_unicode_ci, '; ', ',')
           ) > 0 THEN t.`updated_by`
      ELSE LEFT(CONCAT(t.`updated_by`, '; ', 'recommend_change_purchprod'), v_updated_by_max)
    END
  WHERE
    t.`type` = 'change'
    AND t.`Status_transaction` = 'В ожидании'
    AND t.`Recommend_purchprod` IS NULL
    AND t.`Status_warehouse` IN ('Новая', 'В изготовлении')
    AND COALESCE(m.`sum_qty`, 0) > 0;

  /* 2) same_erp_id_inPurchase > 0, не трогать уже «кол-во в изготовлении» */
  UPDATE `Transactions` t
  INNER JOIN `tmp_recommend_erp_scope` s ON s.`ERP_ID` COLLATE utf8mb4_unicode_ci <=> t.`ERP_ID` COLLATE utf8mb4_unicode_ci
  LEFT JOIN `tmp_sum_erp_purch` p ON p.`ERP_ID` COLLATE utf8mb4_unicode_ci <=> t.`ERP_ID` COLLATE utf8mb4_unicode_ci
  SET
    t.`Recommend_purchprod` = 'Уточнить кол-во в закупке',
    t.`updated_at`         = NOW(),
    t.`updated_by`         = CASE
      WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'recommend_change_purchprod'
      WHEN FIND_IN_SET(
             'recommend_change_purchprod' COLLATE utf8mb4_unicode_ci,
             REPLACE(t.`updated_by` COLLATE utf8mb4_unicode_ci, '; ', ',')
           ) > 0 THEN t.`updated_by`
      ELSE LEFT(CONCAT(t.`updated_by`, '; ', 'recommend_change_purchprod'), v_updated_by_max)
    END
  WHERE
    t.`type` = 'change'
    AND t.`Status_transaction` = 'В ожидании'
    AND t.`Status_warehouse` IN ('Новая', 'В закупке')
    AND NOT (t.`Recommend_purchprod` <=> 'Уточнить кол-во в изготовлении')
    AND COALESCE(p.`sum_qty`, 0) > 0;

  /* 3) same part + изг., не первые две уточнки, отриц. Quantity_change */
  UPDATE `Transactions` t
  INNER JOIN `tmp_recommend_part_scope` s ON s.`pnum` COLLATE utf8mb4_unicode_ci = LEFT(COALESCE(t.`Supplied_component_number`, ''), 255) COLLATE utf8mb4_unicode_ci
  LEFT JOIN `tmp_sum_part_manuf` m ON m.`pnum` COLLATE utf8mb4_unicode_ci = LEFT(COALESCE(t.`Supplied_component_number`, ''), 255) COLLATE utf8mb4_unicode_ci
  SET
    t.`Recommend_purchprod` = 'Уточнить ревизию в изготовлении',
    t.`updated_at`         = NOW(),
    t.`updated_by`         = CASE
      WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'recommend_change_purchprod'
      WHEN FIND_IN_SET(
             'recommend_change_purchprod' COLLATE utf8mb4_unicode_ci,
             REPLACE(t.`updated_by` COLLATE utf8mb4_unicode_ci, '; ', ',')
           ) > 0 THEN t.`updated_by`
      ELSE LEFT(CONCAT(t.`updated_by`, '; ', 'recommend_change_purchprod'), v_updated_by_max)
    END
  WHERE
    t.`type` = 'change'
    AND t.`Status_transaction` = 'В ожидании'
    AND t.`Status_warehouse` IN ('Новая', 'В изготовлении')
    AND t.`Quantity_change` < 0
    AND NOT (t.`Recommend_purchprod` <=> 'Уточнить кол-во в изготовлении')
    AND NOT (t.`Recommend_purchprod` <=> 'Уточнить кол-во в закупке')
    AND (
      COALESCE(m.`sum_qty`, 0)
      - CASE
          WHEN t.`Status_warehouse` = 'В изготовлении' THEN COALESCE(t.`Quantity_change`, 0)
          ELSE 0
        END
    ) > 0;

  /* 4) part + закуп, не первые три, отриц. qty */
  UPDATE `Transactions` t
  INNER JOIN `tmp_recommend_part_scope` s ON s.`pnum` COLLATE utf8mb4_unicode_ci = LEFT(COALESCE(t.`Supplied_component_number`, ''), 255) COLLATE utf8mb4_unicode_ci
  LEFT JOIN `tmp_sum_part_purch` p ON p.`pnum` COLLATE utf8mb4_unicode_ci = LEFT(COALESCE(t.`Supplied_component_number`, ''), 255) COLLATE utf8mb4_unicode_ci
  SET
    t.`Recommend_purchprod` = 'Уточнить ревизию в закупке',
    t.`updated_at`         = NOW(),
    t.`updated_by`         = CASE
      WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'recommend_change_purchprod'
      WHEN FIND_IN_SET(
             'recommend_change_purchprod' COLLATE utf8mb4_unicode_ci,
             REPLACE(t.`updated_by` COLLATE utf8mb4_unicode_ci, '; ', ',')
           ) > 0 THEN t.`updated_by`
      ELSE LEFT(CONCAT(t.`updated_by`, '; ', 'recommend_change_purchprod'), v_updated_by_max)
    END
  WHERE
    t.`type` = 'change'
    AND t.`Status_transaction` = 'В ожидании'
    AND t.`Status_warehouse` IN ('Новая', 'В закупке')
    AND t.`Quantity_change` < 0
    AND NOT (t.`Recommend_purchprod` <=> 'Уточнить кол-во в изготовлении')
    AND NOT (t.`Recommend_purchprod` <=> 'Уточнить кол-во в закупке')
    AND NOT (t.`Recommend_purchprod` <=> 'Уточнить ревизию в изготовлении')
    AND (
      COALESCE(p.`sum_qty`, 0)
      - CASE
          WHEN t.`Status_warehouse` = 'В закупке' THEN COALESCE(t.`Quantity_change`, 0)
          ELSE 0
        END
    ) > 0;

  /* Остаток: по исходным кандидатам — компонентный сценарий (JSON) */
  SELECT JSON_ARRAYAGG(t.id) INTO v_ids
  FROM `Transactions` t
  INNER JOIN `tmp_recommend_purchprod_candidates` k ON k.id = t.id
  WHERE t.`Recommend_purchprod` IS NULL;

  IF v_ids IS NOT NULL AND JSON_TYPE(v_ids) = 'ARRAY' AND JSON_LENGTH(v_ids) > 0 THEN
    CALL `recommend_change_new`(v_ids);
  END IF;

  DROP TEMPORARY TABLE IF EXISTS `tmp_sum_part_purch`;
  DROP TEMPORARY TABLE IF EXISTS `tmp_sum_part_manuf`;
  DROP TEMPORARY TABLE IF EXISTS `tmp_sum_erp_purch`;
  DROP TEMPORARY TABLE IF EXISTS `tmp_sum_erp_manuf`;
  DROP TEMPORARY TABLE IF EXISTS `tmp_recommend_part_scope`;
  DROP TEMPORARY TABLE IF EXISTS `tmp_recommend_erp_scope`;
  DROP TEMPORARY TABLE IF EXISTS `tmp_recommend_purchprod_candidates`;
END$$

DELIMITER ;
