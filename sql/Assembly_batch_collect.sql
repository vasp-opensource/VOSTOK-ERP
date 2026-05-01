-- Assembly_batch_collect: собирает уже назначенные Assembly_batch_id в реестр Assembly_batches.

DELIMITER $$

DROP PROCEDURE IF EXISTS `Assembly_batch_collect`$$

CREATE PROCEDURE `Assembly_batch_collect`()
BEGIN
  INSERT INTO `Assembly_batches` (
    `created_at`,
    `updated_at`,
    `created_by`,
    `updated_by`,
    `Assembly_batch_id`,
    `Supplied_component_number`
  )
  SELECT
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP,
    'Assembly_batch_collect',
    'Assembly_batch_collect',
    src.`Assembly_batch_id`,
    src.`Supplied_component_number`
  FROM (
    SELECT
      LEFT(t.`Assembly_batch_id`, 255) AS `Assembly_batch_id`,
      MIN(LEFT(t.`Supplied_component_number`, 255)) AS `Supplied_component_number`
    FROM `Transactions` t
    WHERE t.`type` COLLATE utf8mb4_unicode_ci = 'change' COLLATE utf8mb4_unicode_ci
      AND t.`Status_transaction` COLLATE utf8mb4_unicode_ci = 'В ожидании' COLLATE utf8mb4_unicode_ci
      AND t.`Assembly_batch_id` IS NOT NULL
      AND TRIM(COALESCE(t.`Assembly_batch_id`, '' COLLATE utf8mb4_unicode_ci)) <> '' COLLATE utf8mb4_unicode_ci
    GROUP BY LEFT(t.`Assembly_batch_id`, 255)
  ) src
  WHERE src.`Assembly_batch_id` IS NOT NULL
    AND NOT EXISTS (
      SELECT 1
      FROM `Assembly_batches` ab
      WHERE ab.`Assembly_batch_id` COLLATE utf8mb4_unicode_ci =
            src.`Assembly_batch_id` COLLATE utf8mb4_unicode_ci
    );

  INSERT INTO `Assembly_batches` (
    `created_at`,
    `updated_at`,
    `created_by`,
    `updated_by`,
    `Assembly_batch_id`,
    `Supplied_component_number`
  )
  SELECT
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP,
    'Assembly_batch_collect',
    'Assembly_batch_collect',
    src.`Assembly_batch_id`,
    src.`Supplied_component_number`
  FROM (
    SELECT
      LEFT(t.`Assembly_batch_id`, 255) AS `Assembly_batch_id`,
      MIN(LEFT(t.`Target_assembly`, 255)) AS `Supplied_component_number`
    FROM `Transactions` t
    WHERE t.`type` COLLATE utf8mb4_unicode_ci = 'move' COLLATE utf8mb4_unicode_ci
      AND t.`Status_transaction` COLLATE utf8mb4_unicode_ci = 'В ожидании' COLLATE utf8mb4_unicode_ci
      AND t.`Assembly_batch_id` IS NOT NULL
      AND TRIM(COALESCE(t.`Assembly_batch_id`, '' COLLATE utf8mb4_unicode_ci)) <> '' COLLATE utf8mb4_unicode_ci
    GROUP BY LEFT(t.`Assembly_batch_id`, 255)
  ) src
  WHERE src.`Assembly_batch_id` IS NOT NULL
    AND NOT EXISTS (
      SELECT 1
      FROM `Assembly_batches` ab
      WHERE ab.`Assembly_batch_id` COLLATE utf8mb4_unicode_ci =
            src.`Assembly_batch_id` COLLATE utf8mb4_unicode_ci
    );
END$$

DELIMITER ;
