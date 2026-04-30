-- assembly_batch_id_create: генерирует уникальный Assembly_batch_id.

DELIMITER $$

DROP PROCEDURE IF EXISTS `assembly_batch_id_create`$$

CREATE PROCEDURE `assembly_batch_id_create`(
  OUT p_Assembly_batch_id VARCHAR(255)
)
BEGIN
  DECLARE v_chars VARCHAR(36) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  DECLARE v_candidate VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL;
  DECLARE v_batch_exists INT DEFAULT 0;

  generate_batch_id: LOOP
    SET v_candidate = CONCAT(
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
            v_candidate COLLATE utf8mb4_unicode_ci
      UNION ALL
      SELECT ab.`Assembly_batch_id`
      FROM `Assembly_batches` ab
      WHERE ab.`Assembly_batch_id` COLLATE utf8mb4_unicode_ci =
            v_candidate COLLATE utf8mb4_unicode_ci
    ) existing_batches;

    IF v_batch_exists = 0 THEN
      SET p_Assembly_batch_id = v_candidate;
      LEAVE generate_batch_id;
    END IF;
  END LOOP;
END$$

DELIMITER ;
