-- erp_batch_orchestrator: очередь батчей и worker-events для управляемого параллельного запуска.
-- Core-последовательность обычного цикла: batch_import -> batch_prework -> batch_recommend -> batch_bot_call -> batch_supervisor -> batch_import_check -> batch_integrity_check -> batch_pause_5s -> batch_kernel -> batch_performance_log.
-- Heavy-цикл раз в 3 минуты: batch_assembly_batches.
-- Heavy-цикл эксклюзивен за счёт общей очереди: другие батчи не ставятся в очередь, пока heavy-задачи pending/running.
-- batch_bot_call включён в core-цепочку и выполняется строго по sequence_no.
-- batch_performance_log запускается в конце цикла, когда batch-логи уже заполнены.
-- Цикл с running-задачей старше 5 минут считается зависшим и освобождает очередь.
-- batch_assembly_batches и batch_bot_call запускаются только через оркестратор (без отдельных таймеров).

DROP EVENT IF EXISTS ev_erp_run_batch;
DROP EVENT IF EXISTS ev_batch_import_27s;
DROP EVENT IF EXISTS ev_batch_recommend_37s;
DROP EVENT IF EXISTS ev_batch_supervisor_23s;
DROP EVENT IF EXISTS ev_batch_integrity_check_37s;
DROP EVENT IF EXISTS ev_batch_kernel_17s;
DROP EVENT IF EXISTS ev_batch_import_check_43s;
DROP EVENT IF EXISTS ev_batch_assembly_batches_47s;
DROP EVENT IF EXISTS ev_batch_performance_log_2m;
DROP EVENT IF EXISTS ev_batch_bot_call_53s;

DROP EVENT IF EXISTS ev_erp_enqueue_cycle_5s;
DROP EVENT IF EXISTS ev_erp_enqueue_heavy_cycle_3m;
DROP EVENT IF EXISTS ev_erp_worker_1_5s;
DROP EVENT IF EXISTS ev_erp_worker_2_5s;
DROP EVENT IF EXISTS ev_erp_worker_3_5s;
DROP EVENT IF EXISTS ev_erp_worker_4_5s;

CREATE TABLE IF NOT EXISTS `erp_batch_queue` (
    `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    `cycle_id` CHAR(36) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
    `batch_name` VARCHAR(128) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
    `batch_group` ENUM('core', 'service') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
    `sequence_no` INT NULL,
    `priority` INT NOT NULL DEFAULT 100,
    `status` ENUM('pending', 'running', 'done', 'failed') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'pending',
    `worker_name` VARCHAR(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
    `started_at` DATETIME(6) NULL,
    `finished_at` DATETIME(6) NULL,
    `duration_ms` DECIMAL(16,3) NULL,
    `attempts` INT NOT NULL DEFAULT 0,
    `error_message` TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
    `created_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    `updated_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    PRIMARY KEY (`id`),
    UNIQUE KEY `uq_erp_batch_queue_cycle_batch` (`cycle_id`, `batch_name`),
    KEY `idx_erp_batch_queue_status_priority` (`status`, `priority`, `id`),
    KEY `idx_erp_batch_queue_cycle_sequence` (`cycle_id`, `batch_group`, `sequence_no`),
    KEY `idx_erp_batch_queue_batch_status` (`batch_name`, `status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `erp_batch_orchestrator_log` (
    `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    `queue_id` BIGINT UNSIGNED NULL,
    `cycle_id` CHAR(36) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
    `batch_name` VARCHAR(128) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
    `worker_name` VARCHAR(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
    `status` ENUM('ENQUEUED', 'STARTED', 'DONE', 'FAILED', 'IDLE') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
    `message` TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
    `created_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (`id`),
    KEY `idx_erp_batch_orchestrator_log_created_at` (`created_at`),
    KEY `idx_erp_batch_orchestrator_log_queue_id` (`queue_id`),
    KEY `idx_erp_batch_orchestrator_log_cycle` (`cycle_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DELIMITER $$

DROP PROCEDURE IF EXISTS erp_enqueue_cycle$$
DROP PROCEDURE IF EXISTS erp_enqueue_heavy_cycle$$

CREATE PROCEDURE erp_enqueue_cycle()
proc: BEGIN
    DECLARE v_lock_ok INT DEFAULT 0;
    DECLARE v_cycle_id CHAR(36) DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        IF v_lock_ok = 1 THEN
            DO RELEASE_LOCK('erp_enqueue_cycle');
        END IF;
        RESIGNAL;
    END;

    SELECT GET_LOCK('erp_enqueue_cycle', 0) INTO v_lock_ok;

    IF COALESCE(v_lock_ok, 0) <> 1 THEN
        LEAVE proc;
    END IF;

    DELETE FROM `erp_batch_queue`
    WHERE `status` IN ('done', 'failed')
      AND `updated_at` < NOW(6) - INTERVAL 3 DAY;

    INSERT INTO `erp_batch_orchestrator_log` (`cycle_id`, `status`, `message`)
    SELECT DISTINCT
        stale.`cycle_id`,
        'FAILED',
        'Recovered: stale ERP batch cycle before enqueue'
    FROM `erp_batch_queue` stale
    WHERE stale.`status` = 'running'
      AND stale.`started_at` < NOW(6) - INTERVAL 5 MINUTE;

    UPDATE `erp_batch_queue`
    SET
        `status` = 'failed',
        `finished_at` = NOW(6),
        `error_message` = 'Recovered: stale ERP batch cycle before enqueue'
    WHERE `cycle_id` IN (
        SELECT stale_cycles.`cycle_id`
        FROM (
            SELECT DISTINCT stale.`cycle_id`
            FROM `erp_batch_queue` stale
            WHERE stale.`status` = 'running'
              AND stale.`started_at` < NOW(6) - INTERVAL 5 MINUTE
        ) stale_cycles
    )
      AND `status` IN ('pending', 'running');

    UPDATE `erp_batch_queue`
    SET
        `status` = 'failed',
        `finished_at` = NOW(6),
        `error_message` = 'Recovered: stale running job before enqueue'
    WHERE `status` = 'running'
      AND `started_at` < NOW(6) - INTERVAL 30 MINUTE;

    UPDATE `erp_batch_queue` q
    INNER JOIN `erp_batch_queue` failed_core
      ON failed_core.`cycle_id` = q.`cycle_id`
     AND failed_core.`batch_group` = 'core'
     AND failed_core.`status` = 'failed'
     AND failed_core.`sequence_no` < q.`sequence_no`
    SET
        q.`status` = 'failed',
        q.`finished_at` = NOW(6),
        q.`error_message` = CONCAT('Skipped: previous core batch failed: ', failed_core.`batch_name`)
    WHERE q.`batch_group` = 'core'
      AND q.`status` = 'pending';

    IF EXISTS (
        SELECT 1
        FROM `erp_batch_queue`
        WHERE `status` IN ('pending', 'running')
        LIMIT 1
    ) THEN
        DO RELEASE_LOCK('erp_enqueue_cycle');
        LEAVE proc;
    END IF;

    SET v_cycle_id = UUID();

    IF NOT EXISTS (
        SELECT 1
        FROM `erp_batch_orchestrator_log`
        WHERE `status` = 'ENQUEUED'
          AND `message` = 'Created ERP heavy batch cycle'
          AND `created_at` >= NOW(6) - INTERVAL 3 MINUTE
        LIMIT 1
    ) THEN
        INSERT INTO `erp_batch_queue` (`cycle_id`, `batch_name`, `batch_group`, `sequence_no`, `priority`)
        VALUES
            (v_cycle_id, 'batch_assembly_batches', 'core', 10, 10);

        INSERT INTO `erp_batch_orchestrator_log` (`cycle_id`, `status`, `message`)
        VALUES (v_cycle_id, 'ENQUEUED', 'Created ERP heavy batch cycle');

        DO RELEASE_LOCK('erp_enqueue_cycle');
        LEAVE proc;
    END IF;

    INSERT INTO `erp_batch_queue` (`cycle_id`, `batch_name`, `batch_group`, `sequence_no`, `priority`)
    VALUES
            (v_cycle_id, 'batch_import', 'core', 10, 10),
            (v_cycle_id, 'batch_prework', 'core', 15, 15),
            (v_cycle_id, 'batch_recommend', 'core', 20, 20),
            (v_cycle_id, 'batch_bot_call', 'core', 25, 25),
            (v_cycle_id, 'batch_supervisor', 'core', 30, 30),
            (v_cycle_id, 'batch_import_check', 'core', 35, 35),
            (v_cycle_id, 'batch_integrity_check', 'core', 40, 40),
            (v_cycle_id, 'batch_pause_5s', 'core', 45, 45),
            (v_cycle_id, 'batch_kernel', 'core', 50, 50),
            (v_cycle_id, 'batch_performance_log', 'core', 60, 60);

    INSERT INTO `erp_batch_orchestrator_log` (`cycle_id`, `status`, `message`)
    VALUES (v_cycle_id, 'ENQUEUED', 'Created ERP batch cycle');

    DO RELEASE_LOCK('erp_enqueue_cycle');
END$$

CREATE PROCEDURE erp_enqueue_heavy_cycle()
proc: BEGIN
    DECLARE v_lock_ok INT DEFAULT 0;
    DECLARE v_cycle_id CHAR(36) DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        IF v_lock_ok = 1 THEN
            DO RELEASE_LOCK('erp_enqueue_cycle');
        END IF;
        RESIGNAL;
    END;

    SELECT GET_LOCK('erp_enqueue_cycle', 0) INTO v_lock_ok;

    IF COALESCE(v_lock_ok, 0) <> 1 THEN
        LEAVE proc;
    END IF;

    DELETE FROM `erp_batch_queue`
    WHERE `status` IN ('done', 'failed')
      AND `updated_at` < NOW(6) - INTERVAL 3 DAY;

    INSERT INTO `erp_batch_orchestrator_log` (`cycle_id`, `status`, `message`)
    SELECT DISTINCT
        stale.`cycle_id`,
        'FAILED',
        'Recovered: stale ERP batch cycle before heavy enqueue'
    FROM `erp_batch_queue` stale
    WHERE stale.`status` = 'running'
      AND stale.`started_at` < NOW(6) - INTERVAL 5 MINUTE;

    UPDATE `erp_batch_queue`
    SET
        `status` = 'failed',
        `finished_at` = NOW(6),
        `error_message` = 'Recovered: stale ERP batch cycle before heavy enqueue'
    WHERE `cycle_id` IN (
        SELECT stale_cycles.`cycle_id`
        FROM (
            SELECT DISTINCT stale.`cycle_id`
            FROM `erp_batch_queue` stale
            WHERE stale.`status` = 'running'
              AND stale.`started_at` < NOW(6) - INTERVAL 5 MINUTE
        ) stale_cycles
    )
      AND `status` IN ('pending', 'running');

    UPDATE `erp_batch_queue` q
    INNER JOIN `erp_batch_queue` failed_core
      ON failed_core.`cycle_id` = q.`cycle_id`
     AND failed_core.`batch_group` = 'core'
     AND failed_core.`status` = 'failed'
     AND failed_core.`sequence_no` < q.`sequence_no`
    SET
        q.`status` = 'failed',
        q.`finished_at` = NOW(6),
        q.`error_message` = CONCAT('Skipped: previous core batch failed: ', failed_core.`batch_name`)
    WHERE q.`batch_group` = 'core'
      AND q.`status` = 'pending';

    IF EXISTS (
        SELECT 1
        FROM `erp_batch_queue`
        WHERE `status` IN ('pending', 'running')
        LIMIT 1
    ) THEN
        DO RELEASE_LOCK('erp_enqueue_cycle');
        LEAVE proc;
    END IF;

    SET v_cycle_id = UUID();

    INSERT INTO `erp_batch_queue` (`cycle_id`, `batch_name`, `batch_group`, `sequence_no`, `priority`)
    VALUES
        (v_cycle_id, 'batch_assembly_batches', 'core', 10, 10);

    INSERT INTO `erp_batch_orchestrator_log` (`cycle_id`, `status`, `message`)
    VALUES (v_cycle_id, 'ENQUEUED', 'Created ERP heavy batch cycle');

    DO RELEASE_LOCK('erp_enqueue_cycle');
END$$

DROP PROCEDURE IF EXISTS erp_batch_worker$$

CREATE PROCEDURE erp_batch_worker(
    IN p_worker_name VARCHAR(64)
)
proc: BEGIN
    DECLARE v_pick_lock INT DEFAULT 0;
    DECLARE v_job_id BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_cycle_id CHAR(36) DEFAULT NULL;
    DECLARE v_batch_name VARCHAR(128) DEFAULT NULL;
    DECLARE v_started_at DATETIME(6) DEFAULT NULL;
    DECLARE v_finished_at DATETIME(6) DEFAULT NULL;
    DECLARE v_sqlstate CHAR(5) DEFAULT NULL;
    DECLARE v_errno INT DEFAULT NULL;
    DECLARE v_error_text TEXT DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1
            v_sqlstate = RETURNED_SQLSTATE,
            v_errno = MYSQL_ERRNO,
            v_error_text = MESSAGE_TEXT;

        SET v_finished_at = NOW(6);

        IF v_job_id IS NOT NULL THEN
            UPDATE `erp_batch_queue`
            SET
                `status` = 'failed',
                `finished_at` = v_finished_at,
                `duration_ms` = CASE
                    WHEN `started_at` IS NULL THEN NULL
                    ELSE ROUND(TIMESTAMPDIFF(MICROSECOND, `started_at`, v_finished_at) / 1000, 3)
                END,
                `error_message` = CONCAT(
                    CASE WHEN v_errno IN (1205, 1213, 3572) THEN 'BLOCKED: ' ELSE '' END,
                    'SQLSTATE=', COALESCE(v_sqlstate, ''),
                    ', ERRNO=', COALESCE(v_errno, 0),
                    ', MSG=', COALESCE(v_error_text, '')
                )
            WHERE `id` = v_job_id;

            INSERT INTO `erp_batch_orchestrator_log` (`queue_id`, `cycle_id`, `batch_name`, `worker_name`, `status`, `message`)
            VALUES (
                v_job_id,
                v_cycle_id,
                v_batch_name,
                p_worker_name,
                'FAILED',
                CONCAT(
                    CASE WHEN v_errno IN (1205, 1213, 3572) THEN 'BLOCKED: ' ELSE '' END,
                    'SQLSTATE=', COALESCE(v_sqlstate, ''),
                    ', ERRNO=', COALESCE(v_errno, 0),
                    ', MSG=', COALESCE(v_error_text, '')
                )
            );

            UPDATE `erp_batch_queue` q
            INNER JOIN `erp_batch_queue` failed_job ON failed_job.`id` = v_job_id
            SET
                q.`status` = 'failed',
                q.`finished_at` = v_finished_at,
                q.`error_message` = CONCAT('Skipped: previous core batch failed: ', v_batch_name)
            WHERE q.`cycle_id` = v_cycle_id
              AND q.`batch_group` = 'core'
              AND q.`status` = 'pending'
              AND failed_job.`batch_group` = 'core'
              AND failed_job.`batch_name` <> 'batch_bot_call'
              AND q.`sequence_no` > failed_job.`sequence_no`;
        END IF;

        IF v_pick_lock = 1 THEN
            DO RELEASE_LOCK('erp_batch_queue_pick');
        END IF;

        IF v_errno NOT IN (1205, 1213, 3572) THEN
            RESIGNAL;
        END IF;
    END;

    SELECT GET_LOCK('erp_batch_queue_pick', 5) INTO v_pick_lock;

    IF COALESCE(v_pick_lock, 0) <> 1 THEN
        LEAVE proc;
    END IF;

    INSERT INTO `erp_batch_orchestrator_log` (`cycle_id`, `status`, `message`)
    SELECT DISTINCT
        stale.`cycle_id`,
        'FAILED',
        CONCAT('Recovered: stale ERP batch cycle before worker pick by ', p_worker_name)
    FROM `erp_batch_queue` stale
    WHERE stale.`status` = 'running'
      AND stale.`started_at` < NOW(6) - INTERVAL 5 MINUTE;

    UPDATE `erp_batch_queue`
    SET
        `status` = 'failed',
        `finished_at` = NOW(6),
        `error_message` = CONCAT('Recovered: stale ERP batch cycle before worker pick by ', p_worker_name)
    WHERE `cycle_id` IN (
        SELECT stale_cycles.`cycle_id`
        FROM (
            SELECT DISTINCT stale.`cycle_id`
            FROM `erp_batch_queue` stale
            WHERE stale.`status` = 'running'
              AND stale.`started_at` < NOW(6) - INTERVAL 5 MINUTE
        ) stale_cycles
    )
      AND `status` IN ('pending', 'running');

    UPDATE `erp_batch_queue` q
    INNER JOIN `erp_batch_queue` failed_core
      ON failed_core.`cycle_id` = q.`cycle_id`
     AND failed_core.`batch_group` = 'core'
     AND failed_core.`status` = 'failed'
     AND failed_core.`sequence_no` < q.`sequence_no`
    SET
        q.`status` = 'failed',
        q.`finished_at` = NOW(6),
        q.`error_message` = CONCAT('Skipped: previous core batch failed: ', failed_core.`batch_name`)
    WHERE q.`batch_group` = 'core'
      AND q.`status` = 'pending';

    SET v_job_id = NULL;
    SET v_cycle_id = NULL;
    SET v_batch_name = NULL;

    SET v_job_id = (
        SELECT q.`id`
        FROM `erp_batch_queue` q
        WHERE q.`status` = 'pending'
          AND (
              (
                  q.`batch_group` = 'service'
                  AND NOT EXISTS (
                      SELECT 1
                      FROM `erp_batch_queue` k
                      WHERE k.`status` = 'running'
                        AND k.`batch_name` = 'batch_kernel'
                  )
              )
              OR
              (
                  q.`batch_group` = 'core'
                  AND NOT EXISTS (
                      SELECT 1
                      FROM `erp_batch_queue` p
                      WHERE p.`cycle_id` = q.`cycle_id`
                        AND p.`batch_group` = 'core'
                        AND p.`sequence_no` < q.`sequence_no`
                        AND p.`status` <> 'done'
                  )
                  AND (
                      q.`batch_name` <> 'batch_kernel'
                      OR NOT EXISTS (
                          SELECT 1
                          FROM `erp_batch_queue` r
                          WHERE r.`status` = 'running'
                      )
                  )
                  AND (
                      q.`batch_name` <> 'batch_kernel'
                      OR NOT EXISTS (
                          SELECT 1
                          FROM `erp_batch_queue` s
                          WHERE s.`cycle_id` = q.`cycle_id`
                            AND s.`batch_group` = 'service'
                            AND s.`status` IN ('pending', 'running')
                      )
                  )
                  AND (
                      q.`batch_name` = 'batch_kernel'
                      OR NOT EXISTS (
                          SELECT 1
                          FROM `erp_batch_queue` k
                          WHERE k.`status` = 'running'
                            AND k.`batch_name` = 'batch_kernel'
                      )
                  )
              )
          )
        ORDER BY
            CASE WHEN q.`batch_group` = 'core' THEN 0 ELSE 1 END,
            q.`priority`,
            q.`id`
        LIMIT 1
    );

    IF v_job_id IS NULL THEN
        DO RELEASE_LOCK('erp_batch_queue_pick');
        LEAVE proc;
    END IF;

    SELECT
        q.`cycle_id`,
        q.`batch_name`
    INTO
        v_cycle_id,
        v_batch_name
    FROM `erp_batch_queue` q
    WHERE q.`id` = v_job_id;

    SET v_started_at = NOW(6);

    UPDATE `erp_batch_queue`
    SET
        `status` = 'running',
        `worker_name` = p_worker_name,
        `started_at` = v_started_at,
        `attempts` = `attempts` + 1,
        `error_message` = NULL
    WHERE `id` = v_job_id;

    INSERT INTO `erp_batch_orchestrator_log` (`queue_id`, `cycle_id`, `batch_name`, `worker_name`, `status`, `message`)
    VALUES (v_job_id, v_cycle_id, v_batch_name, p_worker_name, 'STARTED', 'Worker started batch');

    DO RELEASE_LOCK('erp_batch_queue_pick');
    SET v_pick_lock = 0;

    CASE v_batch_name
        WHEN 'batch_import' THEN CALL batch_import();
        WHEN 'batch_prework' THEN CALL batch_prework();
        WHEN 'batch_recommend' THEN CALL batch_recommend();
        WHEN 'batch_supervisor' THEN CALL batch_supervisor();
        WHEN 'batch_integrity_check' THEN CALL batch_integrity_check();
        WHEN 'batch_pause_5s' THEN DO SLEEP(5);
        WHEN 'batch_kernel' THEN CALL batch_kernel();
        WHEN 'batch_import_check' THEN CALL batch_import_check();
        WHEN 'batch_assembly_batches' THEN CALL batch_assembly_batches();
        WHEN 'batch_bot_call' THEN CALL batch_bot_call();
        WHEN 'batch_performance_log' THEN CALL batch_performance_log();
        ELSE
            SIGNAL SQLSTATE '45000'
                SET MYSQL_ERRNO = 1644,
                    MESSAGE_TEXT = 'Unknown ERP batch name';
    END CASE;

    SET v_finished_at = NOW(6);

    UPDATE `erp_batch_queue`
    SET
        `status` = 'done',
        `finished_at` = v_finished_at,
        `duration_ms` = ROUND(TIMESTAMPDIFF(MICROSECOND, v_started_at, v_finished_at) / 1000, 3)
    WHERE `id` = v_job_id;

    INSERT INTO `erp_batch_orchestrator_log` (`queue_id`, `cycle_id`, `batch_name`, `worker_name`, `status`, `message`)
    VALUES (v_job_id, v_cycle_id, v_batch_name, p_worker_name, 'DONE', 'Worker finished batch');
END$$

DELIMITER ;

CREATE EVENT ev_erp_enqueue_cycle_5s
ON SCHEDULE EVERY 5 SECOND
ON COMPLETION PRESERVE
ENABLE
COMMENT 'ERP orchestrator: enqueue batch cycle'
DO CALL erp_enqueue_cycle();

CREATE EVENT ev_erp_enqueue_heavy_cycle_3m
ON SCHEDULE EVERY 3 MINUTE
ON COMPLETION PRESERVE
ENABLE
COMMENT 'ERP orchestrator: enqueue heavy batch cycle'
DO CALL erp_enqueue_heavy_cycle();

CREATE EVENT ev_erp_worker_1_5s
ON SCHEDULE EVERY 5 SECOND
ON COMPLETION PRESERVE
ENABLE
COMMENT 'ERP orchestrator worker 1'
DO CALL erp_batch_worker('worker_1');

CREATE EVENT ev_erp_worker_2_5s
ON SCHEDULE EVERY 5 SECOND
ON COMPLETION PRESERVE
ENABLE
COMMENT 'ERP orchestrator worker 2'
DO CALL erp_batch_worker('worker_2');

CREATE EVENT ev_erp_worker_3_5s
ON SCHEDULE EVERY 5 SECOND
ON COMPLETION PRESERVE
ENABLE
COMMENT 'ERP orchestrator worker 3'
DO CALL erp_batch_worker('worker_3');

CREATE EVENT ev_erp_worker_4_5s
ON SCHEDULE EVERY 5 SECOND
ON COMPLETION PRESERVE
ENABLE
COMMENT 'ERP orchestrator worker 4'
DO CALL erp_batch_worker('worker_4');
