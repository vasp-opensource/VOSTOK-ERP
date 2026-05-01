-- batch_supervisor: батч supervisor-процедур с отдельным логом supervisor_log.
-- Интервал запуска: каждые 23 секунды.

CREATE TABLE IF NOT EXISTS `supervisor_log` (
    `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    `run_id` CHAR(36) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
    `batch_name` VARCHAR(128) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
    `step_no` INT NOT NULL,
    `procedure_name` VARCHAR(128) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
    `started_at` DATETIME(6) NOT NULL,
    `finished_at` DATETIME(6) NOT NULL,
    `duration_ms` DECIMAL(16,3) NOT NULL,
    `status` ENUM('OK', 'ERROR') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'OK',
    `error_message` TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
    `created_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (`id`),ф
    KEY `idx_supervisor_log_run` (`run_id`),
    KEY `idx_supervisor_log_created_at` (`created_at`),
    KEY `idx_supervisor_log_procedure` (`procedure_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP EVENT IF EXISTS ev_batch_supervisor_23s;

DROP PROCEDURE IF EXISTS batch_supervisor;

DELIMITER $$

CREATE PROCEDURE batch_supervisor()
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

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1
            v_sqlstate = RETURNED_SQLSTATE,
            v_errno = MYSQL_ERRNO,
            v_error_text = MESSAGE_TEXT;

        SET v_step_finished = NOW(6);

        IF v_current_proc IS NOT NULL THEN
            INSERT INTO `supervisor_log` (
                run_id, batch_name, step_no, procedure_name, started_at, finished_at, duration_ms, status, error_message, created_at
            )
            VALUES (
                v_run_id,
                'batch_supervisor',
                v_step_no,
                v_current_proc,
                v_step_started,
                v_step_finished,
                ROUND(TIMESTAMPDIFF(MICROSECOND, v_step_started, v_step_finished) / 1000, 3),
                'ERROR',
                CONCAT('SQLSTATE=', COALESCE(v_sqlstate, ''), ', ERRNO=', COALESCE(v_errno, 0), ', MSG=', COALESCE(v_error_text, '')),
                CURRENT_TIMESTAMP(6)
            );
        END IF;

        IF v_batch_started IS NOT NULL THEN
            INSERT INTO `supervisor_log` (
                run_id, batch_name, step_no, procedure_name, started_at, finished_at, duration_ms, status, error_message, created_at
            )
            VALUES (
                v_run_id,
                'batch_supervisor',
                9999,
                '__batch_total__',
                v_batch_started,
                v_step_finished,
                ROUND(TIMESTAMPDIFF(MICROSECOND, v_batch_started, v_step_finished) / 1000, 3),
                'ERROR',
                CONCAT('Batch failed at ', COALESCE(v_current_proc, 'unknown')),
                CURRENT_TIMESTAMP(6)
            );
        END IF;

        IF v_batch_lock = 1 THEN
            DO RELEASE_LOCK('batch_supervisor');
        END IF;
        RESIGNAL;
    END;

    SET v_run_id = UUID();
    SET v_batch_started = NOW(6);
    SELECT GET_LOCK('batch_supervisor', 0) INTO v_batch_lock;

    IF v_batch_lock = 1 THEN
        SET v_step_no = 1;
        SET v_current_proc = 'supervisor_order';
        SET v_step_started = NOW(6);
        CALL supervisor_order();
        SET v_step_finished = NOW(6);
        INSERT INTO `supervisor_log` (run_id, batch_name, step_no, procedure_name, started_at, finished_at, duration_ms, status, created_at)
        VALUES (v_run_id, 'batch_supervisor', v_step_no, v_current_proc, v_step_started, v_step_finished,
                ROUND(TIMESTAMPDIFF(MICROSECOND, v_step_started, v_step_finished) / 1000, 3), 'OK', CURRENT_TIMESTAMP(6));

        SET v_batch_finished = NOW(6);
        INSERT INTO `supervisor_log` (
            run_id, batch_name, step_no, procedure_name, started_at, finished_at, duration_ms, status, error_message, created_at
        )
        VALUES (
            v_run_id,
            'batch_supervisor',
            9999,
            '__batch_total__',
            v_batch_started,
            v_batch_finished,
            ROUND(TIMESTAMPDIFF(MICROSECOND, v_batch_started, v_batch_finished) / 1000, 3),
            'OK',
            NULL,
            CURRENT_TIMESTAMP(6)
        );

        DO RELEASE_LOCK('batch_supervisor');
    END IF;
END$$

DELIMITER ;

CREATE EVENT ev_batch_supervisor_23s
ON SCHEDULE EVERY 23 SECOND
ON COMPLETION PRESERVE
ENABLE
COMMENT 'ERP: supervisor batch every 23 seconds'
DO CALL batch_supervisor();
