-- batch_integrity_check: батч проверки целостности с отдельным логом запусков.
-- Важно: integrity_check_log уже используется check_data_integrity для найденных нарушений.
-- Лог выполнения батча пишется в integrity_batch_log.
-- Интервал запуска: каждые 37 секунд.

CREATE TABLE IF NOT EXISTS `integrity_batch_log` (
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
    KEY `idx_integrity_batch_log_run` (`run_id`),
    KEY `idx_integrity_batch_log_created_at` (`created_at`),
    KEY `idx_integrity_batch_log_procedure` (`procedure_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP EVENT IF EXISTS ev_batch_integrity_check_37s;

DROP PROCEDURE IF EXISTS batch_integrity_check;

DELIMITER $$

CREATE PROCEDURE batch_integrity_check()
BEGIN
    DECLARE v_batch_lock INT DEFAULT 0;
    DECLARE v_kernel_lock INT DEFAULT 0;
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

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1
            v_sqlstate = RETURNED_SQLSTATE,
            v_errno = MYSQL_ERRNO,
            v_error_text = MESSAGE_TEXT;

        SET v_error_status = CASE WHEN v_errno IN (1205, 1213, 3572) THEN 'BLOCKED' ELSE 'ERROR' END;
        SET v_step_finished = NOW(6);

        IF v_current_proc IS NOT NULL THEN
            INSERT INTO `integrity_batch_log` (
                run_id, batch_name, step_no, procedure_name, started_at, finished_at, duration_ms, status, error_message, created_at
            )
            VALUES (
                v_run_id,
                'batch_integrity_check',
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
            INSERT INTO `integrity_batch_log` (
                run_id, batch_name, step_no, procedure_name, started_at, finished_at, duration_ms, status, error_message, created_at
            )
            VALUES (
                v_run_id,
                'batch_integrity_check',
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
            DO RELEASE_LOCK('batch_integrity_check');
        END IF;
        IF v_kernel_lock = 1 THEN
            DO RELEASE_LOCK('batch_kernel');
        END IF;
        IF v_error_status = 'ERROR' THEN
            RESIGNAL;
        END IF;
    END;

    SET v_run_id = UUID();
    SET v_batch_started = NOW(6);
    SET @erp_batch_blocked_message = NULL;
    SELECT GET_LOCK('batch_integrity_check', 0) INTO v_batch_lock;

    IF v_batch_lock = 1 THEN
        SELECT GET_LOCK('batch_kernel', 0) INTO v_kernel_lock;

        IF v_kernel_lock = 0 THEN
            SET v_batch_finished = NOW(6);
            INSERT INTO `integrity_batch_log` (
                run_id, batch_name, step_no, procedure_name, started_at, finished_at, duration_ms, status, error_message, created_at
            )
            VALUES (
                v_run_id,
                'batch_integrity_check',
                9999,
                '__batch_total__',
                v_batch_started,
                v_batch_finished,
                ROUND(TIMESTAMPDIFF(MICROSECOND, v_batch_started, v_batch_finished) / 1000, 3),
                'BLOCKED',
                'Blocked: batch_kernel is running',
                CURRENT_TIMESTAMP(6)
            );

            DO RELEASE_LOCK('batch_integrity_check');
        ELSE
            SET v_step_no = 1;
            SET v_current_proc = 'check_data_integrity';
            SET v_step_started = NOW(6);
            CALL check_data_integrity();
            IF @erp_batch_blocked_message IS NOT NULL THEN
                SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 3572, MESSAGE_TEXT = @erp_batch_blocked_message;
            END IF;
            SET v_step_finished = NOW(6);
            INSERT INTO `integrity_batch_log` (run_id, batch_name, step_no, procedure_name, started_at, finished_at, duration_ms, status, created_at)
            VALUES (v_run_id, 'batch_integrity_check', v_step_no, v_current_proc, v_step_started, v_step_finished,
                    ROUND(TIMESTAMPDIFF(MICROSECOND, v_step_started, v_step_finished) / 1000, 3), 'OK', CURRENT_TIMESTAMP(6));

            SET v_batch_finished = NOW(6);
            INSERT INTO `integrity_batch_log` (
                run_id, batch_name, step_no, procedure_name, started_at, finished_at, duration_ms, status, error_message, created_at
            )
            VALUES (
                v_run_id,
                'batch_integrity_check',
                9999,
                '__batch_total__',
                v_batch_started,
                v_batch_finished,
                ROUND(TIMESTAMPDIFF(MICROSECOND, v_batch_started, v_batch_finished) / 1000, 3),
                'OK',
                NULL,
                CURRENT_TIMESTAMP(6)
            );

            DO RELEASE_LOCK('batch_kernel');
            DO RELEASE_LOCK('batch_integrity_check');
        END IF;
    ELSE
        SET v_batch_finished = NOW(6);
        INSERT INTO `integrity_batch_log` (
            run_id, batch_name, step_no, procedure_name, started_at, finished_at, duration_ms, status, error_message, created_at
        )
        VALUES (
            v_run_id,
            'batch_integrity_check',
            9999,
            '__batch_total__',
            v_batch_started,
            v_batch_finished,
            ROUND(TIMESTAMPDIFF(MICROSECOND, v_batch_started, v_batch_finished) / 1000, 3),
            'BLOCKED',
            'Blocked: batch_integrity_check lock is already held',
            CURRENT_TIMESTAMP(6)
        );
    END IF;
END$$

DELIMITER ;

CREATE EVENT ev_batch_integrity_check_37s
ON SCHEDULE EVERY 37 SECOND
ON COMPLETION PRESERVE
ENABLE
COMMENT 'ERP: integrity check batch every 37 seconds'
DO CALL batch_integrity_check();
