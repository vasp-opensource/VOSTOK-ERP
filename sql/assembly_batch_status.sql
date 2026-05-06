-- assembly_batch_status: пересчитывает Assembly_batch_status по состоянию строк Transactions.
-- Обрабатываются только строки с непустым Assembly_batch_id и статусом партии <> 'Завершен'.
-- Приоритет правил (сверху вниз): 1..7 согласно постановке задачи.

DELIMITER $$

DROP PROCEDURE IF EXISTS `assembly_batch_status`$$

CREATE PROCEDURE `assembly_batch_status`()
BEGIN
  DECLARE v_updated_by_max INT DEFAULT 2000;

  SELECT COALESCE(c.CHARACTER_MAXIMUM_LENGTH, 2000)
    INTO v_updated_by_max
  FROM information_schema.COLUMNS c
  WHERE c.TABLE_SCHEMA = DATABASE()
    AND c.TABLE_NAME = 'Transactions'
    AND c.COLUMN_NAME = 'updated_by'
  LIMIT 1;

  DROP TEMPORARY TABLE IF EXISTS tmp_assembly_batch_status_stats;
  CREATE TEMPORARY TABLE tmp_assembly_batch_status_stats AS
  SELECT
    t.`Assembly_batch_id` AS assembly_batch_id,
    SUM(t.`type` = 'move') AS move_count,
    SUM(t.`type` = 'change') AS change_count,
    SUM(t.`type` = 'move' AND t.`Status_warehouse` = 'Новая') AS has_move_new,
    SUM(
      t.`type` = 'move'
      AND t.`Status_warehouse` IN ('Ожидание закупки', 'Ожидание изготовления', 'Ожидание поставки')
    ) AS has_move_wait_proc,
    SUM(t.`type` = 'move' AND t.`Status_warehouse` = 'Комплектация') AS has_move_kitting,
    SUM(t.`type` = 'move' AND t.`Status_warehouse` = 'Сборка') AS has_move_assembly,
    SUM(
      t.`type` = 'move'
      AND (t.`Status_transaction` IS NULL OR t.`Status_transaction` = 'В ожидании')
    ) AS open_move_count,
    SUM(
      t.`type` = 'change'
      AND (t.`Status_transaction` IS NULL OR t.`Status_transaction` = 'В ожидании')
    ) AS open_change_count,
    SUM(t.`Status_transaction` IS NULL OR t.`Status_transaction` = 'В ожидании') AS open_any_count
  FROM `Transactions` t
  WHERE t.`Assembly_batch_id` IS NOT NULL
    AND TRIM(COALESCE(t.`Assembly_batch_id`, '')) <> ''
    AND (
      t.`Assembly_batch_status` IS NULL
      OR CONVERT(t.`Assembly_batch_status` USING utf8mb4) COLLATE utf8mb4_unicode_ci <>
         CONVERT('Завершен' USING utf8mb4) COLLATE utf8mb4_unicode_ci
    )
  GROUP BY t.`Assembly_batch_id`;

  DROP TEMPORARY TABLE IF EXISTS tmp_assembly_batch_status_decision;
  CREATE TEMPORARY TABLE tmp_assembly_batch_status_decision AS
  SELECT
    s.assembly_batch_id,
    CASE
      -- 1) Только change, ни одной move.
      WHEN s.move_count = 0 AND s.change_count > 0 THEN 'Нет спецификации'
      -- 2) Есть move со статусом склада "Новая".
      WHEN s.has_move_new > 0 THEN 'Ожидает определения'
      -- 3) Есть move со статусами ожидания закупки/изготовления/поставки.
      WHEN s.has_move_wait_proc > 0 THEN 'В закупке/изготовлении'
      -- 4) Есть move со статусом склада "Комплектация".
      WHEN s.has_move_kitting > 0 THEN 'В комплектации'
      -- 5) Есть move со статусом склада "Сборка".
      WHEN s.has_move_assembly > 0 THEN 'В сборке'
      -- 6) Все move не в "В ожидании", и есть хотя бы один change в "В ожидании".
      WHEN s.move_count > 0 AND s.open_move_count = 0 AND s.open_change_count > 0 THEN 'Готов'
      -- 7) Все строки не в "В ожидании".
      WHEN s.open_any_count = 0 THEN 'Завершен'
      ELSE NULL
    END AS new_status
  FROM tmp_assembly_batch_status_stats s;

  UPDATE `Transactions` t
  INNER JOIN tmp_assembly_batch_status_decision d
    ON d.assembly_batch_id COLLATE utf8mb4_unicode_ci =
       t.`Assembly_batch_id` COLLATE utf8mb4_unicode_ci
  SET
    t.`Assembly_batch_status` = d.new_status,
    t.`updated_by` = CASE
      WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'assembly_batch_status'
      ELSE LEFT(CONCAT(t.`updated_by`, '; ', 'assembly_batch_status'), v_updated_by_max)
    END,
    t.`updated_at` = CURRENT_TIMESTAMP
  WHERE d.new_status IS NOT NULL
    AND (
      t.`Assembly_batch_status` IS NULL
      OR CONVERT(t.`Assembly_batch_status` USING utf8mb4) COLLATE utf8mb4_unicode_ci <>
         CONVERT('Завершен' USING utf8mb4) COLLATE utf8mb4_unicode_ci
    )
    AND (
      t.`Assembly_batch_status` IS NULL
      OR CONVERT(t.`Assembly_batch_status` USING utf8mb4) COLLATE utf8mb4_unicode_ci <>
         CONVERT(d.new_status USING utf8mb4) COLLATE utf8mb4_unicode_ci
    );

  DROP TEMPORARY TABLE IF EXISTS tmp_assembly_batch_status_decision;
  DROP TEMPORARY TABLE IF EXISTS tmp_assembly_batch_status_stats;
END$$

DELIMITER ;
