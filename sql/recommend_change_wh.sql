-- recommend_change_wh: рекомендации по доработке старой ревизии в новую.
-- Вход: отрицательные change-строки в статусе «Ожидает решения».
-- Новые ревизии ищутся по Supplied_component_number среди положительных change-строк
-- в статусах «В изготовлении», «В закупке», «Новая».
-- Требует будущую процедуру recommend_rework(p_transaction_id, p_source).

DELIMITER $$

DROP PROCEDURE IF EXISTS `recommend_change_wh`$$

CREATE PROCEDURE `recommend_change_wh`()
BEGIN
  DECLARE done INT DEFAULT 0;
  DECLARE v_tx_id INT UNSIGNED;
  DECLARE v_source VARCHAR(32);
  DECLARE v_updated_by_max INT DEFAULT 2000;

  DECLARE cur_rework CURSOR FOR
    SELECT id, rework_source
    FROM `tmp_recommend_change_wh_plan`
    WHERE rework_source IS NOT NULL;

  DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;

  SELECT COALESCE(c.CHARACTER_MAXIMUM_LENGTH, 2000)
    INTO v_updated_by_max
  FROM information_schema.COLUMNS c
  WHERE c.TABLE_SCHEMA = DATABASE()
    AND c.TABLE_NAME = 'Transactions'
    AND c.COLUMN_NAME = 'updated_by'
  LIMIT 1;

  DROP TEMPORARY TABLE IF EXISTS `tmp_recommend_change_wh_seed`;
  CREATE TEMPORARY TABLE `tmp_recommend_change_wh_seed` AS
  SELECT
    t.id,
    CAST(t.`ERP_ID` AS CHAR CHARACTER SET utf8mb4) COLLATE utf8mb4_unicode_ci AS `ERP_ID`,
    CAST(LEFT(COALESCE(t.`Supplied_component_number`, ''), 255) AS CHAR CHARACTER SET utf8mb4) COLLATE utf8mb4_unicode_ci AS `pnum`,
    ABS(COALESCE(t.`Quantity_change`, 0)) AS old_revision_quantity
  FROM `Transactions` t
  WHERE t.`type` = 'change'
    AND t.`Status_transaction` = 'В ожидании'
    AND t.`Status_warehouse` = 'Ожидает решения'
    AND COALESCE(t.`Quantity_change`, 0) < 0;
  ALTER TABLE `tmp_recommend_change_wh_seed` ADD PRIMARY KEY (`id`);
  ALTER TABLE `tmp_recommend_change_wh_seed` ADD KEY `idx_rework_seed_pnum` (`pnum`);

  DROP TEMPORARY TABLE IF EXISTS `tmp_recommend_change_wh_new`;
  CREATE TEMPORARY TABLE `tmp_recommend_change_wh_new` AS
  SELECT
    s.id AS seed_id,
    n.id AS new_id,
    CAST(n.`ERP_ID` AS CHAR CHARACTER SET utf8mb4) COLLATE utf8mb4_unicode_ci AS new_erp_id,
    COALESCE(n.`Quantity_change`, 0) AS new_qty
  FROM `tmp_recommend_change_wh_seed` s
  INNER JOIN `Transactions` n
    ON CAST(LEFT(COALESCE(n.`Supplied_component_number`, ''), 255) AS CHAR CHARACTER SET utf8mb4) COLLATE utf8mb4_unicode_ci = s.`pnum` COLLATE utf8mb4_unicode_ci
   AND n.id <> s.id
  WHERE n.`type` = 'change'
    AND n.`Status_transaction` = 'В ожидании'
    AND n.`Status_warehouse` IN ('В изготовлении', 'В закупке', 'Новая')
    AND COALESCE(n.`Quantity_change`, 0) > 0;
  ALTER TABLE `tmp_recommend_change_wh_new` ADD KEY `idx_rework_new_seed` (`seed_id`);
  ALTER TABLE `tmp_recommend_change_wh_new` ADD KEY `idx_rework_new_id` (`new_id`);

  DROP TEMPORARY TABLE IF EXISTS `tmp_recommend_change_wh_new_agg`;
  CREATE TEMPORARY TABLE `tmp_recommend_change_wh_new_agg` AS
  SELECT
    seed_id,
    SUM(COALESCE(new_qty, 0)) AS new_revisions_quantity,
    MAX(new_erp_id) AS rework_to
  FROM `tmp_recommend_change_wh_new`
  GROUP BY seed_id;
  ALTER TABLE `tmp_recommend_change_wh_new_agg` ADD PRIMARY KEY (`seed_id`);

  DROP TEMPORARY TABLE IF EXISTS `tmp_recommend_change_wh_plan`;
  CREATE TEMPORARY TABLE `tmp_recommend_change_wh_plan` AS
  SELECT
    s.id,
    s.`ERP_ID` AS rework_from,
    COALESCE(a.new_revisions_quantity, 0) AS new_revisions_quantity,
    a.rework_to,
    s.old_revision_quantity,
    COALESCE(m.`Quantity_in_warehouse`, 0) AS warehouse_quantity,
    (
      COALESCE(m.`Quantity_in_warehouse`, 0)
      + COALESCE(m.`Quantity_in_kitting`, 0)
      + COALESCE(m.`Quantity_on_shopfloor`, 0)
    ) AS available_quantity,
    GREATEST(s.old_revision_quantity - COALESCE(m.`Quantity_in_warehouse`, 0), 0) AS not_covered_wh,
    GREATEST(
      GREATEST(s.old_revision_quantity - COALESCE(m.`Quantity_in_warehouse`, 0), 0)
      - COALESCE(m.`Quantity_in_kitting`, 0),
      0
    ) AS not_covered_kit,
    GREATEST(
      GREATEST(
        GREATEST(s.old_revision_quantity - COALESCE(m.`Quantity_in_warehouse`, 0), 0)
        - COALESCE(m.`Quantity_in_kitting`, 0),
        0
      )
      - COALESCE(m.`Quantity_on_shopfloor`, 0),
      0
    ) AS not_covered_prod,
    CASE
      WHEN GREATEST(s.old_revision_quantity - COALESCE(m.`Quantity_in_warehouse`, 0), 0) = 0
           AND GREATEST(
             GREATEST(s.old_revision_quantity - COALESCE(m.`Quantity_in_warehouse`, 0), 0)
             - COALESCE(m.`Quantity_in_kitting`, 0),
             0
           ) = 0
           AND GREATEST(
             GREATEST(
               GREATEST(s.old_revision_quantity - COALESCE(m.`Quantity_in_warehouse`, 0), 0)
               - COALESCE(m.`Quantity_in_kitting`, 0),
               0
             )
             - COALESCE(m.`Quantity_on_shopfloor`, 0),
             0
           ) = 0
           AND COALESCE(a.new_revisions_quantity, 0) >= s.old_revision_quantity
        THEN 'warehouse'
      WHEN GREATEST(
             GREATEST(s.old_revision_quantity - COALESCE(m.`Quantity_in_warehouse`, 0), 0)
             - COALESCE(m.`Quantity_in_kitting`, 0),
             0
           ) = 0
           AND GREATEST(
             GREATEST(
               GREATEST(s.old_revision_quantity - COALESCE(m.`Quantity_in_warehouse`, 0), 0)
               - COALESCE(m.`Quantity_in_kitting`, 0),
               0
             )
             - COALESCE(m.`Quantity_on_shopfloor`, 0),
             0
           ) = 0
           AND COALESCE(a.new_revisions_quantity, 0) >= (
             s.old_revision_quantity
             - GREATEST(s.old_revision_quantity - COALESCE(m.`Quantity_in_warehouse`, 0), 0)
           )
        THEN 'kitting'
      WHEN GREATEST(
             GREATEST(
               GREATEST(s.old_revision_quantity - COALESCE(m.`Quantity_in_warehouse`, 0), 0)
               - COALESCE(m.`Quantity_in_kitting`, 0),
               0
             )
             - COALESCE(m.`Quantity_on_shopfloor`, 0),
             0
           ) = 0
           AND GREATEST(
             GREATEST(s.old_revision_quantity - COALESCE(m.`Quantity_in_warehouse`, 0), 0)
             - COALESCE(m.`Quantity_in_kitting`, 0),
             0
           ) > 0
           AND COALESCE(a.new_revisions_quantity, 0) > 0
        THEN 'prod'
      ELSE NULL
    END AS rework_source,
    CASE
      WHEN GREATEST(s.old_revision_quantity - COALESCE(m.`Quantity_in_warehouse`, 0), 0) = 0
           AND COALESCE(a.new_revisions_quantity, 0) > 0
           AND COALESCE(a.new_revisions_quantity, 0) < s.old_revision_quantity
        THEN 'забраковать ИЛИ отменить ИЛИ разбить'
      WHEN GREATEST(s.old_revision_quantity - COALESCE(m.`Quantity_in_warehouse`, 0), 0) = 0
        THEN 'забраковать ИЛИ отменить'
      WHEN GREATEST(
             GREATEST(s.old_revision_quantity - COALESCE(m.`Quantity_in_warehouse`, 0), 0)
             - COALESCE(m.`Quantity_in_kitting`, 0),
             0
           ) = 0
           AND COALESCE(a.new_revisions_quantity, 0) > 0
           AND COALESCE(a.new_revisions_quantity, 0) < s.old_revision_quantity
        THEN 'забраковать ИЛИ отменить ИЛИ разбить'
      WHEN GREATEST(
             GREATEST(s.old_revision_quantity - COALESCE(m.`Quantity_in_warehouse`, 0), 0)
             - COALESCE(m.`Quantity_in_kitting`, 0),
             0
           ) = 0
        THEN 'забраковать ИЛИ отменить'
      WHEN GREATEST(
             GREATEST(
               GREATEST(s.old_revision_quantity - COALESCE(m.`Quantity_in_warehouse`, 0), 0)
               - COALESCE(m.`Quantity_in_kitting`, 0),
               0
             )
             - COALESCE(m.`Quantity_on_shopfloor`, 0),
             0
           ) = 0
           AND COALESCE(a.new_revisions_quantity, 0) > 0
           AND COALESCE(a.new_revisions_quantity, 0) < s.old_revision_quantity
        THEN 'забраковать ИЛИ отменить ИЛИ разбить'
      WHEN GREATEST(
             GREATEST(
               GREATEST(s.old_revision_quantity - COALESCE(m.`Quantity_in_warehouse`, 0), 0)
               - COALESCE(m.`Quantity_in_kitting`, 0),
               0
             )
             - COALESCE(m.`Quantity_on_shopfloor`, 0),
             0
           ) = 0
        THEN 'забраковать ИЛИ отменить'
      WHEN s.old_revision_quantity > (
             COALESCE(m.`Quantity_in_warehouse`, 0)
             + COALESCE(m.`Quantity_in_kitting`, 0)
             + COALESCE(m.`Quantity_on_shopfloor`, 0)
           )
        THEN 'отменить ИЛИ разбить'
      ELSE 'отменить'
    END AS recommend_wh
  FROM `tmp_recommend_change_wh_seed` s
  LEFT JOIN `tmp_recommend_change_wh_new_agg` a ON a.seed_id = s.id
  LEFT JOIN `Main` m ON m.`ERP_ID` COLLATE utf8mb4_unicode_ci = s.`ERP_ID` COLLATE utf8mb4_unicode_ci;
  ALTER TABLE `tmp_recommend_change_wh_plan` ADD PRIMARY KEY (`id`);

  UPDATE `Transactions` t
  INNER JOIN `tmp_recommend_change_wh_plan` p ON p.id = t.id
  SET
    t.`Rework_to` = p.rework_to,
    t.`Rework_from` = p.rework_from,
    t.`Recommend_wh` = CASE WHEN p.rework_source IS NULL THEN p.recommend_wh ELSE t.`Recommend_wh` END,
    t.`Quantity_ordered` = CASE
      WHEN p.rework_source IS NULL
           AND p.recommend_wh = 'забраковать ИЛИ отменить ИЛИ разбить'
        THEN p.new_revisions_quantity
      WHEN p.rework_source IS NULL
           AND p.recommend_wh = 'отменить ИЛИ разбить'
        THEN p.available_quantity
      WHEN p.rework_source IS NULL
           AND p.recommend_wh = 'забраковать ИЛИ отменить'
        THEN 0
      ELSE t.`Quantity_ordered`
    END,
    t.`updated_at` = NOW(),
    t.`updated_by` = CASE
      WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'recommend_change_wh'
      ELSE LEFT(CONCAT(t.`updated_by`, '; ', 'recommend_change_wh'), v_updated_by_max)
    END;

  UPDATE `Transactions` n
  INNER JOIN `tmp_recommend_change_wh_new` rn ON rn.new_id = n.id
  INNER JOIN `tmp_recommend_change_wh_plan` p ON p.id = rn.seed_id
  SET
    n.`Rework_to` = p.rework_to,
    n.`Rework_from` = p.rework_from,
    n.`updated_at` = NOW(),
    n.`updated_by` = CASE
      WHEN n.`updated_by` IS NULL OR TRIM(COALESCE(n.`updated_by`, '')) = '' THEN 'recommend_change_wh'
      ELSE LEFT(CONCAT(n.`updated_by`, '; ', 'recommend_change_wh'), v_updated_by_max)
    END
  WHERE p.rework_source IS NOT NULL;

  OPEN cur_rework;
  rework_loop: LOOP
    FETCH cur_rework INTO v_tx_id, v_source;
    IF done = 1 THEN
      LEAVE rework_loop;
    END IF;

    CALL `recommend_rework`(v_tx_id, v_source);
  END LOOP;
  CLOSE cur_rework;

  DROP TEMPORARY TABLE IF EXISTS `tmp_recommend_change_wh_plan`;
  DROP TEMPORARY TABLE IF EXISTS `tmp_recommend_change_wh_new_agg`;
  DROP TEMPORARY TABLE IF EXISTS `tmp_recommend_change_wh_new`;
  DROP TEMPORARY TABLE IF EXISTS `tmp_recommend_change_wh_seed`;
END$$

DELIMITER ;
