-- batch_bot_call: батч bot_call с отдельным логом bot_call_log.
-- Запуск выполняется через erp_batch_orchestrator как core batch.

CREATE TABLE IF NOT EXISTS `bot_call_log` (
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
    KEY `idx_bot_call_log_run` (`run_id`),
    KEY `idx_bot_call_log_created_at` (`created_at`),
    KEY `idx_bot_call_log_procedure` (`procedure_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP EVENT IF EXISTS ev_batch_bot_call_53s;

DROP PROCEDURE IF EXISTS batch_bot_call;

DELIMITER $$

CREATE PROCEDURE batch_bot_call()
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
    DECLARE v_old_lock_wait_timeout INT DEFAULT NULL;

    DECLARE exp_row_count INT;
    DECLARE exp_approve INT;
    DECLARE purch_purch INT;
    DECLARE purch_byed INT;
    DECLARE purch_manuf INT;
    DECLARE prod_rework INT;
    DECLARE purch_return INT;
    DECLARE purch_cost BIGINT;
    DECLARE prod_kit INT;
    DECLARE prod_assembled INT;
    DECLARE prod_prod INT;
    DECLARE prod_manuf INT;
    DECLARE prod_purch INT;
    DECLARE prod_shipped INT;
    DECLARE prod_loss INT;
    DECLARE prod_return INT;
    DECLARE wh_purch INT;
    DECLARE wh_manuf INT;
    DECLARE wh_return INT;
    DECLARE wh_kit INT;
    DECLARE OTK_manuf INT;
    DECLARE OTK_assembly INT;
    DECLARE OTK_shipped INT;
    DECLARE OTK_loss INT;
    DECLARE sv_choice INT;
    DECLARE sv_replace INT;
    DECLARE replace_to VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1
            v_sqlstate = RETURNED_SQLSTATE,
            v_errno = MYSQL_ERRNO,
            v_error_text = MESSAGE_TEXT;
        SET v_error_status = CASE WHEN v_errno IN (1205, 1213, 3572) THEN 'BLOCKED' ELSE 'ERROR' END;
        SET v_step_finished = NOW(6);

        IF v_current_proc IS NOT NULL THEN
            INSERT INTO `bot_call_log` (
                run_id, batch_name, step_no, procedure_name, started_at, finished_at, duration_ms, status, error_message, created_at
            )
            VALUES (
                v_run_id,
                'batch_bot_call',
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
            INSERT INTO `bot_call_log` (
                run_id, batch_name, step_no, procedure_name, started_at, finished_at, duration_ms, status, error_message, created_at
            )
            VALUES (
                v_run_id,
                'batch_bot_call',
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
            DO RELEASE_LOCK('batch_bot_call');
        END IF;
        IF v_old_lock_wait_timeout IS NOT NULL THEN
            SET SESSION innodb_lock_wait_timeout = v_old_lock_wait_timeout;
        END IF;
        IF v_error_status = 'ERROR' THEN
            RESIGNAL;
        END IF;
    END;

    SET v_run_id = UUID();
    SET v_batch_started = NOW(6);
    SET @erp_batch_blocked_message = NULL;
    SELECT @@SESSION.innodb_lock_wait_timeout INTO v_old_lock_wait_timeout;
    SET SESSION innodb_lock_wait_timeout = 5;
    SELECT GET_LOCK('batch_bot_call', 0) INTO v_batch_lock;

    IF v_batch_lock = 1 THEN
        /* Диапазоны ботов задаются только в bot_parameters. */
        SELECT
            MAX(CASE WHEN bp.`variable_name` = 'exp_row_count'  THEN FLOOR(bp.`value_min` + RAND() * GREATEST(bp.`value_max` - bp.`value_min` + 1, 1)) END),
            MAX(CASE WHEN bp.`variable_name` = 'exp_approve'    THEN FLOOR(bp.`value_min` + RAND() * GREATEST(bp.`value_max` - bp.`value_min` + 1, 1)) END),
            MAX(CASE WHEN bp.`variable_name` = 'purch_purch'    THEN FLOOR(bp.`value_min` + RAND() * GREATEST(bp.`value_max` - bp.`value_min` + 1, 1)) END),
            MAX(CASE WHEN bp.`variable_name` = 'purch_byed'     THEN FLOOR(bp.`value_min` + RAND() * GREATEST(bp.`value_max` - bp.`value_min` + 1, 1)) END),
            MAX(CASE WHEN bp.`variable_name` = 'purch_manuf'    THEN FLOOR(bp.`value_min` + RAND() * GREATEST(bp.`value_max` - bp.`value_min` + 1, 1)) END),
            MAX(CASE WHEN bp.`variable_name` = 'prod_rework'    THEN FLOOR(bp.`value_min` + RAND() * GREATEST(bp.`value_max` - bp.`value_min` + 1, 1)) END),
            MAX(CASE WHEN bp.`variable_name` = 'purch_return'   THEN FLOOR(bp.`value_min` + RAND() * GREATEST(bp.`value_max` - bp.`value_min` + 1, 1)) END),
            MAX(CASE WHEN bp.`variable_name` = 'purch_cost'     THEN FLOOR(bp.`value_min` + RAND() * GREATEST(bp.`value_max` - bp.`value_min` + 1, 1)) END),
            MAX(CASE WHEN bp.`variable_name` = 'prod_kit'       THEN FLOOR(bp.`value_min` + RAND() * GREATEST(bp.`value_max` - bp.`value_min` + 1, 1)) END),
            MAX(CASE WHEN bp.`variable_name` = 'prod_assembled' THEN FLOOR(bp.`value_min` + RAND() * GREATEST(bp.`value_max` - bp.`value_min` + 1, 1)) END),
            MAX(CASE WHEN bp.`variable_name` = 'prod_prod'      THEN FLOOR(bp.`value_min` + RAND() * GREATEST(bp.`value_max` - bp.`value_min` + 1, 1)) END),
            MAX(CASE WHEN bp.`variable_name` = 'prod_manuf'     THEN FLOOR(bp.`value_min` + RAND() * GREATEST(bp.`value_max` - bp.`value_min` + 1, 1)) END),
            MAX(CASE WHEN bp.`variable_name` = 'prod_purch'     THEN FLOOR(bp.`value_min` + RAND() * GREATEST(bp.`value_max` - bp.`value_min` + 1, 1)) END),
            MAX(CASE WHEN bp.`variable_name` = 'prod_shipped'   THEN FLOOR(bp.`value_min` + RAND() * GREATEST(bp.`value_max` - bp.`value_min` + 1, 1)) END),
            MAX(CASE WHEN bp.`variable_name` = 'prod_loss'      THEN FLOOR(bp.`value_min` + RAND() * GREATEST(bp.`value_max` - bp.`value_min` + 1, 1)) END),
            MAX(CASE WHEN bp.`variable_name` = 'prod_return'    THEN FLOOR(bp.`value_min` + RAND() * GREATEST(bp.`value_max` - bp.`value_min` + 1, 1)) END),
            MAX(CASE WHEN bp.`variable_name` = 'wh_purch'       THEN FLOOR(bp.`value_min` + RAND() * GREATEST(bp.`value_max` - bp.`value_min` + 1, 1)) END),
            MAX(CASE WHEN bp.`variable_name` = 'wh_manuf'       THEN FLOOR(bp.`value_min` + RAND() * GREATEST(bp.`value_max` - bp.`value_min` + 1, 1)) END),
            MAX(CASE WHEN bp.`variable_name` = 'wh_return'      THEN FLOOR(bp.`value_min` + RAND() * GREATEST(bp.`value_max` - bp.`value_min` + 1, 1)) END),
            MAX(CASE WHEN bp.`variable_name` = 'wh_kit'         THEN FLOOR(bp.`value_min` + RAND() * GREATEST(bp.`value_max` - bp.`value_min` + 1, 1)) END),
            MAX(CASE WHEN bp.`variable_name` = 'OTK_manuf'      THEN FLOOR(bp.`value_min` + RAND() * GREATEST(bp.`value_max` - bp.`value_min` + 1, 1)) END),
            MAX(CASE WHEN bp.`variable_name` = 'OTK_assembly'   THEN FLOOR(bp.`value_min` + RAND() * GREATEST(bp.`value_max` - bp.`value_min` + 1, 1)) END),
            MAX(CASE WHEN bp.`variable_name` = 'OTK_shipped'    THEN FLOOR(bp.`value_min` + RAND() * GREATEST(bp.`value_max` - bp.`value_min` + 1, 1)) END),
            MAX(CASE WHEN bp.`variable_name` = 'OTK_loss'       THEN FLOOR(bp.`value_min` + RAND() * GREATEST(bp.`value_max` - bp.`value_min` + 1, 1)) END),
            MAX(CASE WHEN bp.`variable_name` = 'sv_choice'      THEN FLOOR(bp.`value_min` + RAND() * GREATEST(bp.`value_max` - bp.`value_min` + 1, 1)) END),
            MAX(CASE WHEN bp.`variable_name` = 'sv_replace'     THEN FLOOR(bp.`value_min` + RAND() * GREATEST(bp.`value_max` - bp.`value_min` + 1, 1)) END)
        INTO
            exp_row_count, exp_approve,
            purch_purch, purch_byed, purch_manuf, prod_rework, purch_return, purch_cost,
            prod_kit, prod_assembled, prod_prod, prod_manuf, prod_purch, prod_shipped, prod_loss, prod_return,
            wh_purch, wh_manuf, wh_return, wh_kit,
            OTK_manuf, OTK_assembly, OTK_shipped, OTK_loss,
            sv_choice, sv_replace
        FROM `bot_parameters` bp
        WHERE bp.`value_min` IS NOT NULL
          AND bp.`value_max` IS NOT NULL;

        SELECT m.`ERP_ID`
          INTO replace_to
        FROM `Main` m
        WHERE m.`ERP_ID` IS NOT NULL
        ORDER BY RAND()
        LIMIT 1;

        SET v_step_no = 1;
        SET v_current_proc = 'bot_export_user';
        SET v_step_started = NOW(6);
        INSERT INTO `bot_call_log` (
            run_id, batch_name, step_no, procedure_name, started_at, finished_at, duration_ms, status, error_message, created_at
        )
        VALUES (
            v_run_id,
            'batch_bot_call',
            v_step_no,
            v_current_proc,
            v_step_started,
            v_step_started,
            0,
            'OK',
            'STARTED',
            CURRENT_TIMESTAMP(6)
        );
        CALL bot_export_user(exp_row_count, exp_approve);
        IF @erp_batch_blocked_message IS NOT NULL THEN
            SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 3572, MESSAGE_TEXT = @erp_batch_blocked_message;
        END IF;
        SET v_step_finished = NOW(6);
        INSERT INTO `bot_call_log` (run_id, batch_name, step_no, procedure_name, started_at, finished_at, duration_ms, status, created_at)
        VALUES (v_run_id, 'batch_bot_call', v_step_no, v_current_proc, v_step_started, v_step_finished,
                ROUND(TIMESTAMPDIFF(MICROSECOND, v_step_started, v_step_finished) / 1000, 3), 'OK', CURRENT_TIMESTAMP(6));

        SET v_step_no = 2;
        SET v_current_proc = 'bot_purhaser';
        SET v_step_started = NOW(6);
        INSERT INTO `bot_call_log` (
            run_id, batch_name, step_no, procedure_name, started_at, finished_at, duration_ms, status, error_message, created_at
        )
        VALUES (
            v_run_id,
            'batch_bot_call',
            v_step_no,
            v_current_proc,
            v_step_started,
            v_step_started,
            0,
            'OK',
            'STARTED',
            CURRENT_TIMESTAMP(6)
        );
        CALL bot_purhaser(purch_purch, purch_byed, purch_manuf, prod_rework, purch_return, purch_cost);
        IF @erp_batch_blocked_message IS NOT NULL THEN
            SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 3572, MESSAGE_TEXT = @erp_batch_blocked_message;
        END IF;
        SET v_step_finished = NOW(6);
        INSERT INTO `bot_call_log` (run_id, batch_name, step_no, procedure_name, started_at, finished_at, duration_ms, status, created_at)
        VALUES (v_run_id, 'batch_bot_call', v_step_no, v_current_proc, v_step_started, v_step_finished,
                ROUND(TIMESTAMPDIFF(MICROSECOND, v_step_started, v_step_finished) / 1000, 3), 'OK', CURRENT_TIMESTAMP(6));

        SET v_step_no = 3;
        SET v_current_proc = 'bot_shopfloor';
        SET v_step_started = NOW(6);
        INSERT INTO `bot_call_log` (
            run_id, batch_name, step_no, procedure_name, started_at, finished_at, duration_ms, status, error_message, created_at
        )
        VALUES (
            v_run_id,
            'batch_bot_call',
            v_step_no,
            v_current_proc,
            v_step_started,
            v_step_started,
            0,
            'OK',
            'STARTED',
            CURRENT_TIMESTAMP(6)
        );
        CALL bot_shopfloor(prod_kit, prod_assembled, prod_prod, prod_manuf, prod_purch, prod_shipped, prod_loss, prod_rework, prod_return);
        IF @erp_batch_blocked_message IS NOT NULL THEN
            SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 3572, MESSAGE_TEXT = @erp_batch_blocked_message;
        END IF;
        SET v_step_finished = NOW(6);
        INSERT INTO `bot_call_log` (run_id, batch_name, step_no, procedure_name, started_at, finished_at, duration_ms, status, created_at)
        VALUES (v_run_id, 'batch_bot_call', v_step_no, v_current_proc, v_step_started, v_step_finished,
                ROUND(TIMESTAMPDIFF(MICROSECOND, v_step_started, v_step_finished) / 1000, 3), 'OK', CURRENT_TIMESTAMP(6));

        SET v_step_no = 4;
        SET v_current_proc = 'bot_warehouse';
        SET v_step_started = NOW(6);
        INSERT INTO `bot_call_log` (
            run_id, batch_name, step_no, procedure_name, started_at, finished_at, duration_ms, status, error_message, created_at
        )
        VALUES (
            v_run_id,
            'batch_bot_call',
            v_step_no,
            v_current_proc,
            v_step_started,
            v_step_started,
            0,
            'OK',
            'STARTED',
            CURRENT_TIMESTAMP(6)
        );
        CALL bot_warehouse(wh_purch, wh_manuf, wh_return, wh_kit);
        IF @erp_batch_blocked_message IS NOT NULL THEN
            SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 3572, MESSAGE_TEXT = @erp_batch_blocked_message;
        END IF;
        SET v_step_finished = NOW(6);
        INSERT INTO `bot_call_log` (run_id, batch_name, step_no, procedure_name, started_at, finished_at, duration_ms, status, created_at)
        VALUES (v_run_id, 'batch_bot_call', v_step_no, v_current_proc, v_step_started, v_step_finished,
                ROUND(TIMESTAMPDIFF(MICROSECOND, v_step_started, v_step_finished) / 1000, 3), 'OK', CURRENT_TIMESTAMP(6));

        SET v_step_no = 5;
        SET v_current_proc = 'bot_OTK';
        SET v_step_started = NOW(6);
        INSERT INTO `bot_call_log` (
            run_id, batch_name, step_no, procedure_name, started_at, finished_at, duration_ms, status, error_message, created_at
        )
        VALUES (
            v_run_id,
            'batch_bot_call',
            v_step_no,
            v_current_proc,
            v_step_started,
            v_step_started,
            0,
            'OK',
            'STARTED',
            CURRENT_TIMESTAMP(6)
        );
        CALL bot_OTK(OTK_manuf, OTK_assembly, OTK_shipped, OTK_loss);
        IF @erp_batch_blocked_message IS NOT NULL THEN
            SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 3572, MESSAGE_TEXT = @erp_batch_blocked_message;
        END IF;
        SET v_step_finished = NOW(6);
        INSERT INTO `bot_call_log` (run_id, batch_name, step_no, procedure_name, started_at, finished_at, duration_ms, status, created_at)
        VALUES (v_run_id, 'batch_bot_call', v_step_no, v_current_proc, v_step_started, v_step_finished,
                ROUND(TIMESTAMPDIFF(MICROSECOND, v_step_started, v_step_finished) / 1000, 3), 'OK', CURRENT_TIMESTAMP(6));

        SET v_step_no = 6;
        SET v_current_proc = 'bot_supervisor';
        SET v_step_started = NOW(6);
        INSERT INTO `bot_call_log` (
            run_id, batch_name, step_no, procedure_name, started_at, finished_at, duration_ms, status, error_message, created_at
        )
        VALUES (
            v_run_id,
            'batch_bot_call',
            v_step_no,
            v_current_proc,
            v_step_started,
            v_step_started,
            0,
            'OK',
            'STARTED',
            CURRENT_TIMESTAMP(6)
        );
        CALL bot_supervisor(sv_choice, sv_replace, replace_to);
        IF @erp_batch_blocked_message IS NOT NULL THEN
            SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 3572, MESSAGE_TEXT = @erp_batch_blocked_message;
        END IF;
        SET v_step_finished = NOW(6);
        INSERT INTO `bot_call_log` (
            run_id, batch_name, step_no, procedure_name, started_at, finished_at, duration_ms, status, created_at
        )
        VALUES (
            v_run_id,
            'batch_bot_call',
            v_step_no,
            v_current_proc,
            v_step_started,
            v_step_finished,
            ROUND(TIMESTAMPDIFF(MICROSECOND, v_step_started, v_step_finished) / 1000, 3),
            'OK',
            CURRENT_TIMESTAMP(6)
        );

        SET v_batch_finished = NOW(6);
        INSERT INTO `bot_call_log` (
            run_id, batch_name, step_no, procedure_name, started_at, finished_at, duration_ms, status, error_message, created_at
        )
        VALUES (
            v_run_id,
            'batch_bot_call',
            9999,
            '__batch_total__',
            v_batch_started,
            v_batch_finished,
            ROUND(TIMESTAMPDIFF(MICROSECOND, v_batch_started, v_batch_finished) / 1000, 3),
            'OK',
            NULL,
            CURRENT_TIMESTAMP(6)
        );

        DO RELEASE_LOCK('batch_bot_call');
        SET SESSION innodb_lock_wait_timeout = v_old_lock_wait_timeout;
    ELSE
        SET v_batch_finished = NOW(6);
        INSERT INTO `bot_call_log` (
            run_id, batch_name, step_no, procedure_name, started_at, finished_at, duration_ms, status, error_message, created_at
        )
        VALUES (
            v_run_id,
            'batch_bot_call',
            9999,
            '__batch_total__',
            v_batch_started,
            v_batch_finished,
            ROUND(TIMESTAMPDIFF(MICROSECOND, v_batch_started, v_batch_finished) / 1000, 3),
            'BLOCKED',
            'Blocked: batch_bot_call lock is already held',
            CURRENT_TIMESTAMP(6)
        );
        SET SESSION innodb_lock_wait_timeout = v_old_lock_wait_timeout;
    END IF;
END$$

DELIMITER ;

