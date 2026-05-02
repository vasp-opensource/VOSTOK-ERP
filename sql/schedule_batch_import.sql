-- batch_import: импортный батч процедур с отдельным логом import_log.
-- Интервал запуска: каждые 27 секунд.

CREATE TABLE IF NOT EXISTS `import_log` (
    `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    `run_id` CHAR(36) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
    `batch_name` VARCHAR(128) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
    `step_no` INT NOT NULL,
    `procedure_name` VARCHAR(128) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
    `started_at` DATETIME(6) NOT NULL,
    `finished_at` DATETIME(6) NOT NULL,
    `duration_ms` DECIMAL(16,3) NOT NULL,
    `status` ENUM('OK', 'ERROR', 'BLOCKED') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'OK',
    `error_message` TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
    `created_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (`id`),
    KEY `idx_import_log_run` (`run_id`),
    KEY `idx_import_log_created_at` (`created_at`),
    KEY `idx_import_log_procedure` (`procedure_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP EVENT IF EXISTS ev_batch_import_27s;

DROP PROCEDURE IF EXISTS batch_import;

DELIMITER $$

CREATE PROCEDURE batch_import()
BEGIN
    DECLARE v_batch_lock INT DEFAULT 0;
    DECLARE v_run_id CHAR(36);
    DECLARE v_batch_started DATETIME(6);
    DECLARE v_batch_finished DATETIME(6);
    DECLARE v_step_started DATETIME(6);
    DECLARE v_step_finished DATETIME(6);
    DECLARE v_step_no INT DEFAULT 0;
    DECLARE v_current_proc VARCHAR(128) DEFAULT NULL;
    DECLARE v_sqlstate CHAR(5) DEFAULT NULL;
    DECLARE v_errno INT DEFAULT NULL;
    DECLARE v_error_text TEXT;
    DECLARE v_error_status VARCHAR(16) DEFAULT 'ERROR';
    DECLARE v_has_blocked TINYINT(1) DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1
            v_sqlstate = RETURNED_SQLSTATE,
            v_errno = MYSQL_ERRNO,
            v_error_text = MESSAGE_TEXT;

        SET v_error_status = CASE WHEN v_errno IN (1205, 1213, 3572) THEN 'BLOCKED' ELSE 'ERROR' END;
        SET v_step_finished = NOW(6);

        IF v_current_proc IS NOT NULL THEN
            INSERT INTO `import_log` (
                run_id, batch_name, step_no, procedure_name, started_at, finished_at, duration_ms, status, error_message, created_at
            )
            VALUES (
                v_run_id,
                'batch_import',
                v_step_no,
                v_current_proc,
                v_step_started,
                v_step_finished,
                ROUND(TIMESTAMPDIFF(MICROSECOND, v_step_started, v_step_finished) / 1000, 3),
                v_error_status,
                CONCAT('SQLSTATE=', COALESCE(v_sqlstate, ''), ', ERRNO=', COALESCE(v_errno, 0), ', MSG=', COALESCE(v_error_text, '')),
                CURRENT_TIMESTAMP(6)
            );
        END IF;

        IF v_batch_started IS NOT NULL THEN
            INSERT INTO `import_log` (
                run_id, batch_name, step_no, procedure_name, started_at, finished_at, duration_ms, status, error_message, created_at
            )
            VALUES (
                v_run_id,
                'batch_import',
                9999,
                '__batch_total__',
                v_batch_started,
                v_step_finished,
                ROUND(TIMESTAMPDIFF(MICROSECOND, v_batch_started, v_step_finished) / 1000, 3),
                v_error_status,
                CONCAT(CASE WHEN v_error_status = 'BLOCKED' THEN 'Batch blocked at ' ELSE 'Batch failed at ' END, COALESCE(v_current_proc, 'unknown')),
                CURRENT_TIMESTAMP(6)
            );
        END IF;

        IF v_batch_lock = 1 THEN
            DO RELEASE_LOCK('batch_import');
        END IF;
        IF v_error_status = 'ERROR' THEN
            RESIGNAL;
        END IF;
    END;

    SET v_run_id = UUID();
    SET v_batch_started = NOW(6);
    SET @erp_batch_blocked_message = NULL;
    SELECT GET_LOCK('batch_import', 0) INTO v_batch_lock;

    IF v_batch_lock = 1 THEN
        SET v_step_no = 1;
        SET v_current_proc = 'import_check';
        SET v_step_started = NOW(6);
        CALL import_check();
        SET v_step_finished = NOW(6);
        IF @erp_batch_blocked_message IS NOT NULL THEN
            SET v_has_blocked = 1;
            INSERT INTO `import_log` (run_id, batch_name, step_no, procedure_name, started_at, finished_at, duration_ms, status, error_message, created_at)
            VALUES (v_run_id, 'batch_import', v_step_no, v_current_proc, v_step_started, v_step_finished,
                    ROUND(TIMESTAMPDIFF(MICROSECOND, v_step_started, v_step_finished) / 1000, 3), 'BLOCKED', @erp_batch_blocked_message, CURRENT_TIMESTAMP(6));
            SET @erp_batch_blocked_message = NULL;
        ELSE
            INSERT INTO `import_log` (run_id, batch_name, step_no, procedure_name, started_at, finished_at, duration_ms, status, created_at)
            VALUES (v_run_id, 'batch_import', v_step_no, v_current_proc, v_step_started, v_step_finished,
                    ROUND(TIMESTAMPDIFF(MICROSECOND, v_step_started, v_step_finished) / 1000, 3), 'OK', CURRENT_TIMESTAMP(6));
        END IF;

        SET v_step_no = 2;
        SET v_current_proc = 'import_do';
        SET v_step_started = NOW(6);
        CALL import_do();
        SET v_step_finished = NOW(6);
        IF @erp_batch_blocked_message IS NOT NULL THEN
            SET v_has_blocked = 1;
            INSERT INTO `import_log` (run_id, batch_name, step_no, procedure_name, started_at, finished_at, duration_ms, status, error_message, created_at)
            VALUES (v_run_id, 'batch_import', v_step_no, v_current_proc, v_step_started, v_step_finished,
                    ROUND(TIMESTAMPDIFF(MICROSECOND, v_step_started, v_step_finished) / 1000, 3), 'BLOCKED', @erp_batch_blocked_message, CURRENT_TIMESTAMP(6));
            SET @erp_batch_blocked_message = NULL;
        ELSE
            INSERT INTO `import_log` (run_id, batch_name, step_no, procedure_name, started_at, finished_at, duration_ms, status, created_at)
            VALUES (v_run_id, 'batch_import', v_step_no, v_current_proc, v_step_started, v_step_finished,
                    ROUND(TIMESTAMPDIFF(MICROSECOND, v_step_started, v_step_finished) / 1000, 3), 'OK', CURRENT_TIMESTAMP(6));
        END IF;

        SET v_batch_finished = NOW(6);
        INSERT INTO `import_log` (
            run_id, batch_name, step_no, procedure_name, started_at, finished_at, duration_ms, status, error_message, created_at
        )
        VALUES (
            v_run_id,
            'batch_import',
            9999,
            '__batch_total__',
            v_batch_started,
            v_batch_finished,
            ROUND(TIMESTAMPDIFF(MICROSECOND, v_batch_started, v_batch_finished) / 1000, 3),
            CASE WHEN v_has_blocked = 1 THEN 'BLOCKED' ELSE 'OK' END,
            CASE WHEN v_has_blocked = 1 THEN 'One or more steps were blocked' ELSE NULL END,
            CURRENT_TIMESTAMP(6)
        );

        DO RELEASE_LOCK('batch_import');
    ELSE
        SET v_batch_finished = NOW(6);
        INSERT INTO `import_log` (
            run_id, batch_name, step_no, procedure_name, started_at, finished_at, duration_ms, status, error_message, created_at
        )
        VALUES (
            v_run_id,
            'batch_import',
            9999,
            '__batch_total__',
            v_batch_started,
            v_batch_finished,
            ROUND(TIMESTAMPDIFF(MICROSECOND, v_batch_started, v_batch_finished) / 1000, 3),
            'BLOCKED',
            'Blocked: batch_import lock is already held',
            CURRENT_TIMESTAMP(6)
        );
    END IF;
END$$

DELIMITER ;

CREATE EVENT ev_batch_import_27s
ON SCHEDULE EVERY 27 SECOND
ON COMPLETION PRESERVE
ENABLE
COMMENT 'ERP: import batch every 27 seconds'
DO CALL batch_import();
