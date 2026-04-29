-- assembly_batch_set: назначает сборочные партии открытым change и связанным move.

DELIMITER $$

DROP PROCEDURE IF EXISTS `assembly_batch_set`$$

CREATE PROCEDURE `assembly_batch_set`()
BEGIN
  DECLARE v_id INT UNSIGNED DEFAULT NULL;
  DECLARE v_supplied_component_number VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL;
  DECLARE v_target_assembly TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL;
  DECLARE v_component_name TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL;
  DECLARE v_batch_id VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL;
  DECLARE v_batch_name TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL;
  DECLARE v_move_project TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL;
  DECLARE v_move_advanced_group TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL;
  DECLARE v_updated_by_max INT DEFAULT 2000;
  DECLARE v_chars VARCHAR(36) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  DECLARE v_batch_exists INT DEFAULT 0;

  SELECT COALESCE(c.CHARACTER_MAXIMUM_LENGTH, 2000)
    INTO v_updated_by_max
  FROM information_schema.COLUMNS c
  WHERE c.TABLE_SCHEMA = DATABASE()
    AND c.TABLE_NAME = 'Transactions'
    AND c.COLUMN_NAME = 'updated_by'
  LIMIT 1;

  batch_loop: LOOP
    SET v_id = NULL;
    SET v_supplied_component_number = NULL;
    SET v_target_assembly = NULL;
    SET v_component_name = NULL;
    SET v_batch_id = NULL;
    SET v_batch_name = NULL;
    SET v_move_project = NULL;
    SET v_move_advanced_group = NULL;

    SELECT
      t.`id`,
      LEFT(COALESCE(t.`Supplied_component_number`, ''), 255),
      t.`Target_assembly`,
      t.`Component_name`
    INTO
      v_id,
      v_supplied_component_number,
      v_target_assembly,
      v_component_name
    FROM `Transactions` t
    WHERE t.`type` COLLATE utf8mb4_unicode_ci = 'change' COLLATE utf8mb4_unicode_ci
      AND t.`Status_transaction` COLLATE utf8mb4_unicode_ci = 'В ожидании' COLLATE utf8mb4_unicode_ci
      AND t.`Assembly_batch_id` IS NULL
      AND t.`Component_type` COLLATE utf8mb4_unicode_ci IN (
        'Сборочная единица' COLLATE utf8mb4_unicode_ci,
        'Комплект' COLLATE utf8mb4_unicode_ci,
        'Комплекс' COLLATE utf8mb4_unicode_ci
      )
    ORDER BY t.`id`
    LIMIT 1;

    IF v_id IS NULL THEN
      LEAVE batch_loop;
    END IF;

    SELECT
      ab.`Assembly_batch_id`,
      ab.`Assembly_batch_name`
    INTO
      v_batch_id,
      v_batch_name
    FROM `Assembly_batches` ab
    WHERE ab.`Supplied_component_number` COLLATE utf8mb4_unicode_ci =
          v_supplied_component_number COLLATE utf8mb4_unicode_ci
    ORDER BY ab.`id`
    LIMIT 1;

    IF v_batch_id IS NULL OR TRIM(COALESCE(v_batch_id, '' COLLATE utf8mb4_unicode_ci)) = '' COLLATE utf8mb4_unicode_ci THEN
      SET v_batch_name = v_component_name;

      generate_batch_id: LOOP
        SET v_batch_id = CONCAT(
          SUBSTRING(v_chars, FLOOR(1 + RAND() * 36), 1),
          SUBSTRING(v_chars, FLOOR(1 + RAND() * 36), 1),
          SUBSTRING(v_chars, FLOOR(1 + RAND() * 36), 1),
          SUBSTRING(v_chars, FLOOR(1 + RAND() * 36), 1),
          SUBSTRING(v_chars, FLOOR(1 + RAND() * 36), 1),
          SUBSTRING(v_chars, FLOOR(1 + RAND() * 36), 1)
        );

        SELECT COUNT(*)
          INTO v_batch_exists
        FROM (
          SELECT t.`Assembly_batch_id`
          FROM `Transactions` t
          WHERE t.`Assembly_batch_id` COLLATE utf8mb4_unicode_ci =
                v_batch_id COLLATE utf8mb4_unicode_ci
          UNION ALL
          SELECT ab.`Assembly_batch_id`
          FROM `Assembly_batches` ab
          WHERE ab.`Assembly_batch_id` COLLATE utf8mb4_unicode_ci =
                v_batch_id COLLATE utf8mb4_unicode_ci
        ) existing_batches;

        IF v_batch_exists = 0 THEN
          LEAVE generate_batch_id;
        END IF;
      END LOOP;

      INSERT INTO `Assembly_batches` (
        `created_at`,
        `updated_at`,
        `created_by`,
        `updated_by`,
        `Assembly_batch_id`,
        `Assembly_batch_name`,
        `Assembly_batch_status`,
        `Assembly_batch_priority`,
        `Target_assembly`,
        `Supplied_component_number`
      )
      VALUES (
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP,
        'assembly_batch_set',
        'assembly_batch_set',
        v_batch_id,
        v_batch_name,
        NULL,
        NULL,
        v_target_assembly,
        v_supplied_component_number
      );
    END IF;

    UPDATE `Transactions` t
    SET
      t.`Assembly_batch_id` = v_batch_id,
      t.`Assembly_batch_name` = v_batch_name,
      t.`Assembly_batch_status` = NULL,
      t.`Assembly_batch_priority` = NULL,
      t.`updated_at` = CURRENT_TIMESTAMP,
      t.`updated_by` = CASE
        WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '' COLLATE utf8mb4_unicode_ci)) = '' COLLATE utf8mb4_unicode_ci THEN 'assembly_batch_set'
        WHEN FIND_IN_SET(
               'assembly_batch_set' COLLATE utf8mb4_unicode_ci,
               REPLACE(t.`updated_by` COLLATE utf8mb4_unicode_ci, '; ' COLLATE utf8mb4_unicode_ci, ',' COLLATE utf8mb4_unicode_ci)
             ) > 0 THEN t.`updated_by`
        ELSE LEFT(CONCAT(t.`updated_by`, '; ', 'assembly_batch_set'), v_updated_by_max)
      END
    WHERE t.`type` COLLATE utf8mb4_unicode_ci = 'change' COLLATE utf8mb4_unicode_ci
      AND t.`Status_transaction` COLLATE utf8mb4_unicode_ci = 'В ожидании' COLLATE utf8mb4_unicode_ci
      AND t.`Assembly_batch_id` IS NULL
      AND t.`id` = v_id;

    UPDATE `Transactions` t
    SET
      t.`Assembly_batch_id` = v_batch_id,
      t.`Assembly_batch_name` = v_batch_name,
      t.`Assembly_batch_status` = NULL,
      t.`Assembly_batch_priority` = NULL,
      t.`updated_at` = CURRENT_TIMESTAMP,
      t.`updated_by` = CASE
        WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '' COLLATE utf8mb4_unicode_ci)) = '' COLLATE utf8mb4_unicode_ci THEN 'assembly_batch_set'
        WHEN FIND_IN_SET(
               'assembly_batch_set' COLLATE utf8mb4_unicode_ci,
               REPLACE(t.`updated_by` COLLATE utf8mb4_unicode_ci, '; ' COLLATE utf8mb4_unicode_ci, ',' COLLATE utf8mb4_unicode_ci)
             ) > 0 THEN t.`updated_by`
        ELSE LEFT(CONCAT(t.`updated_by`, '; ', 'assembly_batch_set'), v_updated_by_max)
      END
    WHERE t.`type` COLLATE utf8mb4_unicode_ci = 'move' COLLATE utf8mb4_unicode_ci
      AND t.`Status_transaction` COLLATE utf8mb4_unicode_ci = 'В ожидании' COLLATE utf8mb4_unicode_ci
      AND t.`Assembly_batch_id` IS NULL
      AND LEFT(COALESCE(t.`Target_assembly`, ''), 255) COLLATE utf8mb4_unicode_ci =
          v_supplied_component_number COLLATE utf8mb4_unicode_ci;

    SELECT
      MIN(t.`Project`),
      MIN(t.`Advanced_group`)
    INTO
      v_move_project,
      v_move_advanced_group
    FROM `Transactions` t
    WHERE t.`type` COLLATE utf8mb4_unicode_ci = 'move' COLLATE utf8mb4_unicode_ci
      AND t.`Status_transaction` COLLATE utf8mb4_unicode_ci = 'В ожидании' COLLATE utf8mb4_unicode_ci
      AND t.`Assembly_batch_id` COLLATE utf8mb4_unicode_ci = v_batch_id COLLATE utf8mb4_unicode_ci
      AND LEFT(COALESCE(t.`Target_assembly`, ''), 255) COLLATE utf8mb4_unicode_ci =
          v_supplied_component_number COLLATE utf8mb4_unicode_ci;

    IF v_move_project IS NOT NULL OR v_move_advanced_group IS NOT NULL THEN
      UPDATE `Assembly_batches` ab
      SET
        ab.`Project` = v_move_project,
        ab.`Advanced_group` = v_move_advanced_group,
        ab.`updated_at` = CURRENT_TIMESTAMP,
        ab.`updated_by` = 'assembly_batch_set'
      WHERE ab.`Assembly_batch_id` COLLATE utf8mb4_unicode_ci =
            v_batch_id COLLATE utf8mb4_unicode_ci;
    END IF;
  END LOOP;

  UPDATE `Transactions` t
  INNER JOIN `Assembly_batches` ab
    ON LEFT(COALESCE(t.`Target_assembly`, ''), 255) COLLATE utf8mb4_unicode_ci =
       ab.`Supplied_component_number` COLLATE utf8mb4_unicode_ci
  SET
    t.`Assembly_batch_id` = ab.`Assembly_batch_id`,
    t.`Assembly_batch_name` = ab.`Assembly_batch_name`,
    t.`updated_at` = CURRENT_TIMESTAMP,
    t.`updated_by` = CASE
      WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '' COLLATE utf8mb4_unicode_ci)) = '' COLLATE utf8mb4_unicode_ci THEN 'assembly_batch_set'
      WHEN FIND_IN_SET(
             'assembly_batch_set' COLLATE utf8mb4_unicode_ci,
             REPLACE(t.`updated_by` COLLATE utf8mb4_unicode_ci, '; ' COLLATE utf8mb4_unicode_ci, ',' COLLATE utf8mb4_unicode_ci)
           ) > 0 THEN t.`updated_by`
      ELSE LEFT(CONCAT(t.`updated_by`, '; ', 'assembly_batch_set'), v_updated_by_max)
    END
  WHERE t.`type` COLLATE utf8mb4_unicode_ci = 'move' COLLATE utf8mb4_unicode_ci
    AND t.`Status_transaction` COLLATE utf8mb4_unicode_ci = 'В ожидании' COLLATE utf8mb4_unicode_ci
    AND t.`Assembly_batch_id` IS NULL
    AND ab.`Assembly_batch_id` IS NOT NULL
    AND TRIM(COALESCE(ab.`Assembly_batch_id`, '' COLLATE utf8mb4_unicode_ci)) <> '' COLLATE utf8mb4_unicode_ci;

  UPDATE `Assembly_batches` ab
  INNER JOIN (
    SELECT
      ab2.`Assembly_batch_id`,
      MIN(t.`Project`) AS `Project`,
      MIN(t.`Advanced_group`) AS `Advanced_group`
    FROM `Assembly_batches` ab2
    INNER JOIN `Transactions` t
      ON LEFT(COALESCE(t.`Target_assembly`, ''), 255) COLLATE utf8mb4_unicode_ci =
         ab2.`Supplied_component_number` COLLATE utf8mb4_unicode_ci
    WHERE t.`type` COLLATE utf8mb4_unicode_ci = 'move' COLLATE utf8mb4_unicode_ci
      AND t.`Status_transaction` COLLATE utf8mb4_unicode_ci = 'В ожидании' COLLATE utf8mb4_unicode_ci
      AND (
        ab2.`Project` IS NULL
        OR TRIM(COALESCE(ab2.`Project`, '' COLLATE utf8mb4_unicode_ci)) = '' COLLATE utf8mb4_unicode_ci
        OR ab2.`Advanced_group` IS NULL
        OR TRIM(COALESCE(ab2.`Advanced_group`, '' COLLATE utf8mb4_unicode_ci)) = '' COLLATE utf8mb4_unicode_ci
      )
    GROUP BY ab2.`Assembly_batch_id`
  ) mv ON mv.`Assembly_batch_id` COLLATE utf8mb4_unicode_ci =
          ab.`Assembly_batch_id` COLLATE utf8mb4_unicode_ci
  SET
    ab.`Project` = CASE
      WHEN ab.`Project` IS NULL OR TRIM(COALESCE(ab.`Project`, '' COLLATE utf8mb4_unicode_ci)) = '' COLLATE utf8mb4_unicode_ci THEN mv.`Project`
      ELSE ab.`Project`
    END,
    ab.`Advanced_group` = CASE
      WHEN ab.`Advanced_group` IS NULL OR TRIM(COALESCE(ab.`Advanced_group`, '' COLLATE utf8mb4_unicode_ci)) = '' COLLATE utf8mb4_unicode_ci THEN mv.`Advanced_group`
      ELSE ab.`Advanced_group`
    END,
    ab.`updated_at` = CURRENT_TIMESTAMP,
    ab.`updated_by` = 'assembly_batch_set';
END$$

DELIMITER ;
