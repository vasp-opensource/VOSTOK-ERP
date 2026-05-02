-- performance_log_collect: сводит batch-log таблицы в общий performance_log.
-- Период выборки: последние 2 минуты, только строки __batch_total__.

DELIMITER $$

DROP PROCEDURE IF EXISTS performance_log_collect$$

CREATE PROCEDURE performance_log_collect()
BEGIN
    DECLARE v_run_id CHAR(36);
    DECLARE v_created_at DATETIME(6);
    DECLARE v_old_group_concat_max_len BIGINT UNSIGNED DEFAULT 1024;

    SET v_run_id = UUID();
    SET v_created_at = CURRENT_TIMESTAMP(6);
    SET v_old_group_concat_max_len = @@SESSION.group_concat_max_len;
    SET SESSION group_concat_max_len = 200000;

    DROP TEMPORARY TABLE IF EXISTS tmp_performance_log_collect;
    CREATE TEMPORARY TABLE tmp_performance_log_collect (
        `step_no` INT NOT NULL,
        `procedure_name` VARCHAR(128) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
        `started_at` DATETIME(6) NOT NULL,
        `finished_at` DATETIME(6) NOT NULL,
        `duration_ms` DECIMAL(16,3) NOT NULL,
        `status` ENUM('OK', 'ERROR', 'BLOCKED') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'OK',
        `error_message` TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

    INSERT INTO tmp_performance_log_collect (`step_no`, `procedure_name`, `started_at`, `finished_at`, `duration_ms`, `status`, `error_message`)
    SELECT
        1,
        'kernel_log',
        MIN(`started_at`),
        MIN(`finished_at`),
        MAX(`duration_ms`),
        CASE
            WHEN SUM(CASE WHEN `status` = 'ERROR' THEN 1 ELSE 0 END) > 0 THEN 'ERROR'
            WHEN SUM(CASE WHEN `status` = 'BLOCKED' THEN 1 ELSE 0 END) > 0 THEN 'BLOCKED'
            ELSE 'OK'
        END,
        GROUP_CONCAT(NULLIF(TRIM(COALESCE(`error_message`, '')), '') ORDER BY `created_at` SEPARATOR '; ')
    FROM `kernel_log`
    WHERE `procedure_name` = '__batch_total__'
      AND `created_at` >= NOW(6) - INTERVAL 2 MINUTE
    HAVING COUNT(*) > 0;

    INSERT INTO tmp_performance_log_collect (`step_no`, `procedure_name`, `started_at`, `finished_at`, `duration_ms`, `status`, `error_message`)
    SELECT
        2,
        'import_log',
        MIN(`started_at`),
        MIN(`finished_at`),
        MAX(`duration_ms`),
        CASE
            WHEN SUM(CASE WHEN `status` = 'ERROR' THEN 1 ELSE 0 END) > 0 THEN 'ERROR'
            WHEN SUM(CASE WHEN `status` = 'BLOCKED' THEN 1 ELSE 0 END) > 0 THEN 'BLOCKED'
            ELSE 'OK'
        END,
        GROUP_CONCAT(NULLIF(TRIM(COALESCE(`error_message`, '')), '') ORDER BY `created_at` SEPARATOR '; ')
    FROM `import_log`
    WHERE `procedure_name` = '__batch_total__'
      AND `created_at` >= NOW(6) - INTERVAL 2 MINUTE
    HAVING COUNT(*) > 0;

    INSERT INTO tmp_performance_log_collect (`step_no`, `procedure_name`, `started_at`, `finished_at`, `duration_ms`, `status`, `error_message`)
    SELECT
        3,
        'integrity_batch_log',
        MIN(`started_at`),
        MIN(`finished_at`),
        MAX(`duration_ms`),
        CASE
            WHEN SUM(CASE WHEN `status` = 'ERROR' THEN 1 ELSE 0 END) > 0 THEN 'ERROR'
            WHEN SUM(CASE WHEN `status` = 'BLOCKED' THEN 1 ELSE 0 END) > 0 THEN 'BLOCKED'
            ELSE 'OK'
        END,
        GROUP_CONCAT(NULLIF(TRIM(COALESCE(`error_message`, '')), '') ORDER BY `created_at` SEPARATOR '; ')
    FROM `integrity_batch_log`
    WHERE `procedure_name` = '__batch_total__'
      AND `created_at` >= NOW(6) - INTERVAL 2 MINUTE
    HAVING COUNT(*) > 0;

    INSERT INTO tmp_performance_log_collect (`step_no`, `procedure_name`, `started_at`, `finished_at`, `duration_ms`, `status`, `error_message`)
    SELECT
        4,
        'import_check_log',
        MIN(`started_at`),
        MIN(`finished_at`),
        MAX(`duration_ms`),
        CASE
            WHEN SUM(CASE WHEN `status` = 'ERROR' THEN 1 ELSE 0 END) > 0 THEN 'ERROR'
            WHEN SUM(CASE WHEN `status` = 'BLOCKED' THEN 1 ELSE 0 END) > 0 THEN 'BLOCKED'
            ELSE 'OK'
        END,
        GROUP_CONCAT(NULLIF(TRIM(COALESCE(`error_message`, '')), '') ORDER BY `created_at` SEPARATOR '; ')
    FROM `import_check_log`
    WHERE `procedure_name` = '__batch_total__'
      AND `created_at` >= NOW(6) - INTERVAL 2 MINUTE
    HAVING COUNT(*) > 0;

    INSERT INTO tmp_performance_log_collect (`step_no`, `procedure_name`, `started_at`, `finished_at`, `duration_ms`, `status`, `error_message`)
    SELECT
        5,
        'recommend_log',
        MIN(`started_at`),
        MIN(`finished_at`),
        MAX(`duration_ms`),
        CASE
            WHEN SUM(CASE WHEN `status` = 'ERROR' THEN 1 ELSE 0 END) > 0 THEN 'ERROR'
            WHEN SUM(CASE WHEN `status` = 'BLOCKED' THEN 1 ELSE 0 END) > 0 THEN 'BLOCKED'
            ELSE 'OK'
        END,
        GROUP_CONCAT(NULLIF(TRIM(COALESCE(`error_message`, '')), '') ORDER BY `created_at` SEPARATOR '; ')
    FROM `recommend_log`
    WHERE `procedure_name` = '__batch_total__'
      AND `created_at` >= NOW(6) - INTERVAL 2 MINUTE
    HAVING COUNT(*) > 0;

    INSERT INTO tmp_performance_log_collect (`step_no`, `procedure_name`, `started_at`, `finished_at`, `duration_ms`, `status`, `error_message`)
    SELECT
        6,
        'supervisor_log',
        MIN(`started_at`),
        MIN(`finished_at`),
        MAX(`duration_ms`),
        CASE
            WHEN SUM(CASE WHEN `status` = 'ERROR' THEN 1 ELSE 0 END) > 0 THEN 'ERROR'
            WHEN SUM(CASE WHEN `status` = 'BLOCKED' THEN 1 ELSE 0 END) > 0 THEN 'BLOCKED'
            ELSE 'OK'
        END,
        GROUP_CONCAT(NULLIF(TRIM(COALESCE(`error_message`, '')), '') ORDER BY `created_at` SEPARATOR '; ')
    FROM `supervisor_log`
    WHERE `procedure_name` = '__batch_total__'
      AND `created_at` >= NOW(6) - INTERVAL 2 MINUTE
    HAVING COUNT(*) > 0;

    INSERT INTO tmp_performance_log_collect (`step_no`, `procedure_name`, `started_at`, `finished_at`, `duration_ms`, `status`, `error_message`)
    SELECT
        7,
        'assembly_batches_log',
        MIN(`started_at`),
        MIN(`finished_at`),
        MAX(`duration_ms`),
        CASE
            WHEN SUM(CASE WHEN `status` = 'ERROR' THEN 1 ELSE 0 END) > 0 THEN 'ERROR'
            WHEN SUM(CASE WHEN `status` = 'BLOCKED' THEN 1 ELSE 0 END) > 0 THEN 'BLOCKED'
            ELSE 'OK'
        END,
        GROUP_CONCAT(NULLIF(TRIM(COALESCE(`error_message`, '')), '') ORDER BY `created_at` SEPARATOR '; ')
    FROM `assembly_batches_log`
    WHERE `procedure_name` = '__batch_total__'
      AND `created_at` >= NOW(6) - INTERVAL 2 MINUTE
    HAVING COUNT(*) > 0;

    INSERT INTO tmp_performance_log_collect (`step_no`, `procedure_name`, `started_at`, `finished_at`, `duration_ms`, `status`, `error_message`)
    SELECT
        8,
        'bot_call_log',
        MIN(`started_at`),
        MIN(`finished_at`),
        MAX(`duration_ms`),
        CASE
            WHEN SUM(CASE WHEN `status` = 'ERROR' THEN 1 ELSE 0 END) > 0 THEN 'ERROR'
            WHEN SUM(CASE WHEN `status` = 'BLOCKED' THEN 1 ELSE 0 END) > 0 THEN 'BLOCKED'
            ELSE 'OK'
        END,
        GROUP_CONCAT(NULLIF(TRIM(COALESCE(`error_message`, '')), '') ORDER BY `created_at` SEPARATOR '; ')
    FROM `bot_call_log`
    WHERE `procedure_name` = '__batch_total__'
      AND `created_at` >= NOW(6) - INTERVAL 2 MINUTE
    HAVING COUNT(*) > 0;

    INSERT INTO `performance_log` (
        `run_id`,
        `batch_name`,
        `step_no`,
        `procedure_name`,
        `started_at`,
        `finished_at`,
        `duration_ms`,
        `status`,
        `error_message`,
        `created_at`
    )
    SELECT
        v_run_id,
        'performance_log_collect',
        `step_no`,
        `procedure_name`,
        `started_at`,
        `finished_at`,
        `duration_ms`,
        `status`,
        `error_message`,
        v_created_at
    FROM tmp_performance_log_collect
    ORDER BY `step_no`;

    INSERT INTO `performance_log` (
        `run_id`,
        `batch_name`,
        `step_no`,
        `procedure_name`,
        `started_at`,
        `finished_at`,
        `duration_ms`,
        `status`,
        `error_message`,
        `created_at`
    )
    SELECT
        v_run_id,
        'performance_log_collect',
        9999,
        '__batch_total__',
        MIN(`started_at`),
        MAX(`finished_at`),
        SUM(`duration_ms`),
        CASE
            WHEN SUM(CASE WHEN `status` = 'ERROR' THEN 1 ELSE 0 END) > 0 THEN 'ERROR'
            WHEN SUM(CASE WHEN `status` = 'BLOCKED' THEN 1 ELSE 0 END) > 0 THEN 'BLOCKED'
            ELSE 'OK'
        END,
        GROUP_CONCAT(NULLIF(TRIM(COALESCE(`error_message`, '')), '') ORDER BY `step_no` SEPARATOR '; '),
        v_created_at
    FROM tmp_performance_log_collect
    HAVING COUNT(*) > 0;

    DROP TEMPORARY TABLE IF EXISTS tmp_performance_log_collect;
    SET SESSION group_concat_max_len = v_old_group_concat_max_len;
END$$

DELIMITER ;
