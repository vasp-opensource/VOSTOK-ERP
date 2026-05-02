-- batch_kernel: kernel-батч процедур с отдельным логом kernel_log.
-- Интервал запуска: каждые 17 секунд.

CREATE TABLE IF NOT EXISTS `kernel_log` (
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
    KEY `idx_kernel_log_run` (`run_id`),
    KEY `idx_kernel_log_created_at` (`created_at`),
    KEY `idx_kernel_log_procedure` (`procedure_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP EVENT IF EXISTS ev_batch_kernel_17s;

DROP PROCEDURE IF EXISTS batch_kernel;

DELIMITER $$

CREATE PROCEDURE batch_kernel()
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
    DECLARE v_notify_recipient VARCHAR(255) DEFAULT 'vpyzhyanov@vostk.su';

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1
            v_sqlstate = RETURNED_SQLSTATE,
            v_errno = MYSQL_ERRNO,
            v_error_text = MESSAGE_TEXT;
        SET v_error_status = CASE WHEN v_errno IN (1205, 1213, 3572) THEN 'BLOCKED' ELSE 'ERROR' END;
        SET v_step_finished = NOW(6);

        IF v_current_proc IS NOT NULL THEN
            INSERT INTO `kernel_log` (
                run_id, batch_name, step_no, procedure_name, started_at, finished_at, duration_ms, status, error_message, created_at
            )
            VALUES (
                v_run_id,
                'batch_kernel',
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
            INSERT INTO `kernel_log` (
                run_id, batch_name, step_no, procedure_name, started_at, finished_at, duration_ms, status, error_message, created_at
            )
            VALUES (
                v_run_id,
                'batch_kernel',
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
            DO RELEASE_LOCK('batch_kernel');
        END IF;
        IF v_error_status = 'ERROR' THEN
            RESIGNAL;
        END IF;
    END;

    SET v_run_id = UUID();
    SET v_batch_started = NOW(6);
    SET @erp_batch_blocked_message = NULL;
    SELECT GET_LOCK('batch_kernel', 0) INTO v_batch_lock;

    IF v_batch_lock = 1 THEN
        SET v_step_no = 1;
        SET v_current_proc = 'ch_merge_same_advGroup';
        SET v_step_started = NOW(6);
        CALL ch_merge_same_advGroup();
        IF @erp_batch_blocked_message IS NOT NULL THEN
            SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 3572, MESSAGE_TEXT = @erp_batch_blocked_message;
        END IF;
        SET v_step_finished = NOW(6);
        INSERT INTO `kernel_log` (run_id, batch_name, step_no, procedure_name, started_at, finished_at, duration_ms, status, created_at)
        VALUES (v_run_id, 'batch_kernel', v_step_no, v_current_proc, v_step_started, v_step_finished,
                ROUND(TIMESTAMPDIFF(MICROSECOND, v_step_started, v_step_finished) / 1000, 3), 'OK', CURRENT_TIMESTAMP(6));

        SET v_step_no = 2;
        SET v_current_proc = 'ch_outside_to_ownProd';
        SET v_step_started = NOW(6);
        CALL ch_outside_to_ownProd();
        IF @erp_batch_blocked_message IS NOT NULL THEN
            SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 3572, MESSAGE_TEXT = @erp_batch_blocked_message;
        END IF;
        SET v_step_finished = NOW(6);
        INSERT INTO `kernel_log` (run_id, batch_name, step_no, procedure_name, started_at, finished_at, duration_ms, status, created_at)
        VALUES (v_run_id, 'batch_kernel', v_step_no, v_current_proc, v_step_started, v_step_finished,
                ROUND(TIMESTAMPDIFF(MICROSECOND, v_step_started, v_step_finished) / 1000, 3), 'OK', CURRENT_TIMESTAMP(6));

        SET v_step_no = 3;
        SET v_current_proc = 'ch_outside_to_purch';
        SET v_step_started = NOW(6);
        CALL ch_outside_to_purch();
        IF @erp_batch_blocked_message IS NOT NULL THEN
            SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 3572, MESSAGE_TEXT = @erp_batch_blocked_message;
        END IF;
        SET v_step_finished = NOW(6);
        INSERT INTO `kernel_log` (run_id, batch_name, step_no, procedure_name, started_at, finished_at, duration_ms, status, created_at)
        VALUES (v_run_id, 'batch_kernel', v_step_no, v_current_proc, v_step_started, v_step_finished,
                ROUND(TIMESTAMPDIFF(MICROSECOND, v_step_started, v_step_finished) / 1000, 3), 'OK', CURRENT_TIMESTAMP(6));

        SET v_step_no = 4;
        SET v_current_proc = 'ch_ownprod_to_wh';
        SET v_step_started = NOW(6);
        CALL ch_ownprod_to_wh();
        IF @erp_batch_blocked_message IS NOT NULL THEN
            SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 3572, MESSAGE_TEXT = @erp_batch_blocked_message;
        END IF;
        SET v_step_finished = NOW(6);
        INSERT INTO `kernel_log` (run_id, batch_name, step_no, procedure_name, started_at, finished_at, duration_ms, status, created_at)
        VALUES (v_run_id, 'batch_kernel', v_step_no, v_current_proc, v_step_started, v_step_finished,
                ROUND(TIMESTAMPDIFF(MICROSECOND, v_step_started, v_step_finished) / 1000, 3), 'OK', CURRENT_TIMESTAMP(6));

        SET v_step_no = 5;
        SET v_current_proc = 'ch_purch_to_wh';
        SET v_step_started = NOW(6);
        CALL ch_purch_to_wh();
        IF @erp_batch_blocked_message IS NOT NULL THEN
            SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 3572, MESSAGE_TEXT = @erp_batch_blocked_message;
        END IF;
        SET v_step_finished = NOW(6);
        INSERT INTO `kernel_log` (run_id, batch_name, step_no, procedure_name, started_at, finished_at, duration_ms, status, created_at)
        VALUES (v_run_id, 'batch_kernel', v_step_no, v_current_proc, v_step_started, v_step_finished,
                ROUND(TIMESTAMPDIFF(MICROSECOND, v_step_started, v_step_finished) / 1000, 3), 'OK', CURRENT_TIMESTAMP(6));

        SET v_step_no = 6;
        SET v_current_proc = 'move_kit_to_shopfloor';
        SET v_step_started = NOW(6);
        CALL move_kit_to_shopfloor();
        IF @erp_batch_blocked_message IS NOT NULL THEN
            SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 3572, MESSAGE_TEXT = @erp_batch_blocked_message;
        END IF;
        SET v_step_finished = NOW(6);
        INSERT INTO `kernel_log` (run_id, batch_name, step_no, procedure_name, started_at, finished_at, duration_ms, status, created_at)
        VALUES (v_run_id, 'batch_kernel', v_step_no, v_current_proc, v_step_started, v_step_finished,
                ROUND(TIMESTAMPDIFF(MICROSECOND, v_step_started, v_step_finished) / 1000, 3), 'OK', CURRENT_TIMESTAMP(6));

        SET v_step_no = 7;
        SET v_current_proc = 'move_shop_to_fin';
        SET v_step_started = NOW(6);
        CALL move_shop_to_fin();
        IF @erp_batch_blocked_message IS NOT NULL THEN
            SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 3572, MESSAGE_TEXT = @erp_batch_blocked_message;
        END IF;
        SET v_step_finished = NOW(6);
        INSERT INTO `kernel_log` (run_id, batch_name, step_no, procedure_name, started_at, finished_at, duration_ms, status, created_at)
        VALUES (v_run_id, 'batch_kernel', v_step_no, v_current_proc, v_step_started, v_step_finished,
                ROUND(TIMESTAMPDIFF(MICROSECOND, v_step_started, v_step_finished) / 1000, 3), 'OK', CURRENT_TIMESTAMP(6));

        SET v_step_no = 8;
        SET v_current_proc = 'move_shop_to_wh';
        SET v_step_started = NOW(6);
        CALL move_shop_to_wh();
        IF @erp_batch_blocked_message IS NOT NULL THEN
            SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 3572, MESSAGE_TEXT = @erp_batch_blocked_message;
        END IF;
        SET v_step_finished = NOW(6);
        INSERT INTO `kernel_log` (run_id, batch_name, step_no, procedure_name, started_at, finished_at, duration_ms, status, created_at)
        VALUES (v_run_id, 'batch_kernel', v_step_no, v_current_proc, v_step_started, v_step_finished,
                ROUND(TIMESTAMPDIFF(MICROSECOND, v_step_started, v_step_finished) / 1000, 3), 'OK', CURRENT_TIMESTAMP(6));

        SET v_step_no = 9;
        SET v_current_proc = 'return_shopfloor_to_wh';
        SET v_step_started = NOW(6);
        CALL return_shopfloor_to_wh();
        IF @erp_batch_blocked_message IS NOT NULL THEN
            SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 3572, MESSAGE_TEXT = @erp_batch_blocked_message;
        END IF;
        SET v_step_finished = NOW(6);
        INSERT INTO `kernel_log` (run_id, batch_name, step_no, procedure_name, started_at, finished_at, duration_ms, status, created_at)
        VALUES (v_run_id, 'batch_kernel', v_step_no, v_current_proc, v_step_started, v_step_finished,
                ROUND(TIMESTAMPDIFF(MICROSECOND, v_step_started, v_step_finished) / 1000, 3), 'OK', CURRENT_TIMESTAMP(6));

        SET v_step_no = 10;
        SET v_current_proc = 'return_kit_to_wh';
        SET v_step_started = NOW(6);
        CALL return_kit_to_wh();
        IF @erp_batch_blocked_message IS NOT NULL THEN
            SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 3572, MESSAGE_TEXT = @erp_batch_blocked_message;
        END IF;
        SET v_step_finished = NOW(6);
        INSERT INTO `kernel_log` (run_id, batch_name, step_no, procedure_name, started_at, finished_at, duration_ms, status, created_at)
        VALUES (v_run_id, 'batch_kernel', v_step_no, v_current_proc, v_step_started, v_step_finished,
                ROUND(TIMESTAMPDIFF(MICROSECOND, v_step_started, v_step_finished) / 1000, 3), 'OK', CURRENT_TIMESTAMP(6));

        SET v_step_no = 11;
        SET v_current_proc = 'deficit_wh';
        SET v_step_started = NOW(6);
        CALL deficit_wh();
        IF @erp_batch_blocked_message IS NOT NULL THEN
            SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 3572, MESSAGE_TEXT = @erp_batch_blocked_message;
        END IF;
        SET v_step_finished = NOW(6);
        INSERT INTO `kernel_log` (run_id, batch_name, step_no, procedure_name, started_at, finished_at, duration_ms, status, created_at)
        VALUES (v_run_id, 'batch_kernel', v_step_no, v_current_proc, v_step_started, v_step_finished,
                ROUND(TIMESTAMPDIFF(MICROSECOND, v_step_started, v_step_finished) / 1000, 3), 'OK', CURRENT_TIMESTAMP(6));

        SET v_step_no = 12;
        SET v_current_proc = 'deficit_supply';
        SET v_step_started = NOW(6);
        CALL deficit_supply();
        IF @erp_batch_blocked_message IS NOT NULL THEN
            SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 3572, MESSAGE_TEXT = @erp_batch_blocked_message;
        END IF;
        SET v_step_finished = NOW(6);
        INSERT INTO `kernel_log` (run_id, batch_name, step_no, procedure_name, started_at, finished_at, duration_ms, status, created_at)
        VALUES (v_run_id, 'batch_kernel', v_step_no, v_current_proc, v_step_started, v_step_finished,
                ROUND(TIMESTAMPDIFF(MICROSECOND, v_step_started, v_step_finished) / 1000, 3), 'OK', CURRENT_TIMESTAMP(6));

        SET v_step_no = 13;
        SET v_current_proc = 'notify_integrity_check_email';
        SET v_step_started = NOW(6);
        CALL notify_integrity_check_email(v_notify_recipient);
        SET v_step_finished = NOW(6);
        INSERT INTO `kernel_log` (run_id, batch_name, step_no, procedure_name, started_at, finished_at, duration_ms, status, created_at)
        VALUES (v_run_id, 'batch_kernel', v_step_no, v_current_proc, v_step_started, v_step_finished,
                ROUND(TIMESTAMPDIFF(MICROSECOND, v_step_started, v_step_finished) / 1000, 3), 'OK', CURRENT_TIMESTAMP(6));

        SET v_step_no = 14;
        SET v_current_proc = 'return_shopfloor_to_wh_direct';
        SET v_step_started = NOW(6);
        CALL return_shopfloor_to_wh_direct();
        IF @erp_batch_blocked_message IS NOT NULL THEN
            SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 3572, MESSAGE_TEXT = @erp_batch_blocked_message;
        END IF;
        SET v_step_finished = NOW(6);
        INSERT INTO `kernel_log` (run_id, batch_name, step_no, procedure_name, started_at, finished_at, duration_ms, status, created_at)
        VALUES (v_run_id, 'batch_kernel', v_step_no, v_current_proc, v_step_started, v_step_finished,
                ROUND(TIMESTAMPDIFF(MICROSECOND, v_step_started, v_step_finished) / 1000, 3), 'OK', CURRENT_TIMESTAMP(6));

        SET v_batch_finished = NOW(6);
        INSERT INTO `kernel_log` (
            run_id, batch_name, step_no, procedure_name, started_at, finished_at, duration_ms, status, error_message, created_at
        )
        VALUES (
            v_run_id,
            'batch_kernel',
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
    ELSE
        SET v_batch_finished = NOW(6);
        INSERT INTO `kernel_log` (
            run_id, batch_name, step_no, procedure_name, started_at, finished_at, duration_ms, status, error_message, created_at
        )
        VALUES (
            v_run_id,
            'batch_kernel',
            9999,
            '__batch_total__',
            v_batch_started,
            v_batch_finished,
            ROUND(TIMESTAMPDIFF(MICROSECOND, v_batch_started, v_batch_finished) / 1000, 3),
            'BLOCKED',
            'Blocked: batch_kernel lock is already held',
            CURRENT_TIMESTAMP(6)
        );
    END IF;
END$$

DELIMITER ;

CREATE EVENT ev_batch_kernel_17s
ON SCHEDULE EVERY 17 SECOND
ON COMPLETION PRESERVE
ENABLE
COMMENT 'ERP: kernel batch every 17 seconds'
DO CALL batch_kernel();
