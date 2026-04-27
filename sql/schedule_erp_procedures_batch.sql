-- Планировщик: каждые 30 с вызывает цепочку бизнес-процедур.
-- Версия с поминутным профилированием шагов в performance_log.
-- move_wh_to_shopfloor исключен из батча по требованию.

DROP EVENT IF EXISTS ev_erp_run_batch;

DROP PROCEDURE IF EXISTS run_erp_scheduled_batch;

DELIMITER $$

CREATE PROCEDURE run_erp_scheduled_batch()
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
            INSERT INTO performance_log (
                run_id, batch_name, step_no, procedure_name, started_at, finished_at, duration_ms, status, error_message, created_at
            )
            VALUES (
                v_run_id,
                'run_erp_scheduled_batch',
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
            INSERT INTO performance_log (
                run_id, batch_name, step_no, procedure_name, started_at, finished_at, duration_ms, status, error_message, created_at
            )
            VALUES (
                v_run_id,
                'run_erp_scheduled_batch',
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
            DO RELEASE_LOCK('run_erp_scheduled_batch');
        END IF;
        RESIGNAL;
    END;

    SET v_run_id = UUID();
    SET v_batch_started = NOW(6);
    SELECT GET_LOCK('run_erp_scheduled_batch', 0) INTO v_batch_lock;

    IF v_batch_lock = 1 THEN
        SET v_step_no = 1;
        SET v_current_proc = 'ch_merge_same_advGroup';
        SET v_step_started = NOW(6);
        CALL ch_merge_same_advGroup();
        SET v_step_finished = NOW(6);
        INSERT INTO performance_log (run_id, batch_name, step_no, procedure_name, started_at, finished_at, duration_ms, status, created_at)
        VALUES (v_run_id, 'run_erp_scheduled_batch', v_step_no, v_current_proc, v_step_started, v_step_finished,
                ROUND(TIMESTAMPDIFF(MICROSECOND, v_step_started, v_step_finished) / 1000, 3), 'OK', CURRENT_TIMESTAMP(6));

        SET v_step_no = 2;
        SET v_current_proc = 'ch_outside_to_ownProd';
        SET v_step_started = NOW(6);
        CALL ch_outside_to_ownProd();
        SET v_step_finished = NOW(6);
        INSERT INTO performance_log (run_id, batch_name, step_no, procedure_name, started_at, finished_at, duration_ms, status, created_at)
        VALUES (v_run_id, 'run_erp_scheduled_batch', v_step_no, v_current_proc, v_step_started, v_step_finished,
                ROUND(TIMESTAMPDIFF(MICROSECOND, v_step_started, v_step_finished) / 1000, 3), 'OK', CURRENT_TIMESTAMP(6));

        SET v_step_no = 3;
        SET v_current_proc = 'ch_outside_to_purch';
        SET v_step_started = NOW(6);
        CALL ch_outside_to_purch();
        SET v_step_finished = NOW(6);
        INSERT INTO performance_log (run_id, batch_name, step_no, procedure_name, started_at, finished_at, duration_ms, status, created_at)
        VALUES (v_run_id, 'run_erp_scheduled_batch', v_step_no, v_current_proc, v_step_started, v_step_finished,
                ROUND(TIMESTAMPDIFF(MICROSECOND, v_step_started, v_step_finished) / 1000, 3), 'OK', CURRENT_TIMESTAMP(6));

        SET v_step_no = 4;
        SET v_current_proc = 'ch_ownprod_to_wh';
        SET v_step_started = NOW(6);
        CALL ch_ownprod_to_wh();
        SET v_step_finished = NOW(6);
        INSERT INTO performance_log (run_id, batch_name, step_no, procedure_name, started_at, finished_at, duration_ms, status, created_at)
        VALUES (v_run_id, 'run_erp_scheduled_batch', v_step_no, v_current_proc, v_step_started, v_step_finished,
                ROUND(TIMESTAMPDIFF(MICROSECOND, v_step_started, v_step_finished) / 1000, 3), 'OK', CURRENT_TIMESTAMP(6));

        SET v_step_no = 5;
        SET v_current_proc = 'ch_purch_to_wh';
        SET v_step_started = NOW(6);
        CALL ch_purch_to_wh();
        SET v_step_finished = NOW(6);
        INSERT INTO performance_log (run_id, batch_name, step_no, procedure_name, started_at, finished_at, duration_ms, status, created_at)
        VALUES (v_run_id, 'run_erp_scheduled_batch', v_step_no, v_current_proc, v_step_started, v_step_finished,
                ROUND(TIMESTAMPDIFF(MICROSECOND, v_step_started, v_step_finished) / 1000, 3), 'OK', CURRENT_TIMESTAMP(6));

        SET v_step_no = 6;
        SET v_current_proc = 'move_kit_to_shopfloor';
        SET v_step_started = NOW(6);
        CALL move_kit_to_shopfloor();
        SET v_step_finished = NOW(6);
        INSERT INTO performance_log (run_id, batch_name, step_no, procedure_name, started_at, finished_at, duration_ms, status, created_at)
        VALUES (v_run_id, 'run_erp_scheduled_batch', v_step_no, v_current_proc, v_step_started, v_step_finished,
                ROUND(TIMESTAMPDIFF(MICROSECOND, v_step_started, v_step_finished) / 1000, 3), 'OK', CURRENT_TIMESTAMP(6));

        SET v_step_no = 7;
        SET v_current_proc = 'move_shop_to_fin';
        SET v_step_started = NOW(6);
        CALL move_shop_to_fin();
        SET v_step_finished = NOW(6);
        INSERT INTO performance_log (run_id, batch_name, step_no, procedure_name, started_at, finished_at, duration_ms, status, created_at)
        VALUES (v_run_id, 'run_erp_scheduled_batch', v_step_no, v_current_proc, v_step_started, v_step_finished,
                ROUND(TIMESTAMPDIFF(MICROSECOND, v_step_started, v_step_finished) / 1000, 3), 'OK', CURRENT_TIMESTAMP(6));

        SET v_step_no = 8;
        SET v_current_proc = 'move_shop_to_wh';
        SET v_step_started = NOW(6);
        CALL move_shop_to_wh();
        SET v_step_finished = NOW(6);
        INSERT INTO performance_log (run_id, batch_name, step_no, procedure_name, started_at, finished_at, duration_ms, status, created_at)
        VALUES (v_run_id, 'run_erp_scheduled_batch', v_step_no, v_current_proc, v_step_started, v_step_finished,
                ROUND(TIMESTAMPDIFF(MICROSECOND, v_step_started, v_step_finished) / 1000, 3), 'OK', CURRENT_TIMESTAMP(6));

        SET v_step_no = 9;
        SET v_current_proc = 'return_shopfloor_to_wh';
        SET v_step_started = NOW(6);
        CALL return_shopfloor_to_wh();
        SET v_step_finished = NOW(6);
        INSERT INTO performance_log (run_id, batch_name, step_no, procedure_name, started_at, finished_at, duration_ms, status, created_at)
        VALUES (v_run_id, 'run_erp_scheduled_batch', v_step_no, v_current_proc, v_step_started, v_step_finished,
                ROUND(TIMESTAMPDIFF(MICROSECOND, v_step_started, v_step_finished) / 1000, 3), 'OK', CURRENT_TIMESTAMP(6));

        SET v_step_no = 10;
        SET v_current_proc = 'deficit_wh';
        SET v_step_started = NOW(6);
        CALL deficit_wh();
        SET v_step_finished = NOW(6);
        INSERT INTO performance_log (run_id, batch_name, step_no, procedure_name, started_at, finished_at, duration_ms, status, created_at)
        VALUES (v_run_id, 'run_erp_scheduled_batch', v_step_no, v_current_proc, v_step_started, v_step_finished,
                ROUND(TIMESTAMPDIFF(MICROSECOND, v_step_started, v_step_finished) / 1000, 3), 'OK', CURRENT_TIMESTAMP(6));

        SET v_step_no = 11;
        SET v_current_proc = 'deficit_supply';
        SET v_step_started = NOW(6);
        CALL deficit_supply();
        SET v_step_finished = NOW(6);
        INSERT INTO performance_log (run_id, batch_name, step_no, procedure_name, started_at, finished_at, duration_ms, status, created_at)
        VALUES (v_run_id, 'run_erp_scheduled_batch', v_step_no, v_current_proc, v_step_started, v_step_finished,
                ROUND(TIMESTAMPDIFF(MICROSECOND, v_step_started, v_step_finished) / 1000, 3), 'OK', CURRENT_TIMESTAMP(6));

        SET v_step_no = 12;
        SET v_current_proc = 'import_check';
        SET v_step_started = NOW(6);
        CALL import_check();
        SET v_step_finished = NOW(6);
        INSERT INTO performance_log (run_id, batch_name, step_no, procedure_name, started_at, finished_at, duration_ms, status, created_at)
        VALUES (v_run_id, 'run_erp_scheduled_batch', v_step_no, v_current_proc, v_step_started, v_step_finished,
                ROUND(TIMESTAMPDIFF(MICROSECOND, v_step_started, v_step_finished) / 1000, 3), 'OK', CURRENT_TIMESTAMP(6));

        SET v_step_no = 13;
        SET v_current_proc = 'import_do';
        SET v_step_started = NOW(6);
        CALL import_do();
        SET v_step_finished = NOW(6);
        INSERT INTO performance_log (run_id, batch_name, step_no, procedure_name, started_at, finished_at, duration_ms, status, created_at)
        VALUES (v_run_id, 'run_erp_scheduled_batch', v_step_no, v_current_proc, v_step_started, v_step_finished,
                ROUND(TIMESTAMPDIFF(MICROSECOND, v_step_started, v_step_finished) / 1000, 3), 'OK', CURRENT_TIMESTAMP(6));

        SET v_step_no = 14;
        SET v_current_proc = 'check_data_integrity';
        SET v_step_started = NOW(6);
        CALL check_data_integrity();
        SET v_step_finished = NOW(6);
        INSERT INTO performance_log (run_id, batch_name, step_no, procedure_name, started_at, finished_at, duration_ms, status, created_at)
        VALUES (v_run_id, 'run_erp_scheduled_batch', v_step_no, v_current_proc, v_step_started, v_step_finished,
                ROUND(TIMESTAMPDIFF(MICROSECOND, v_step_started, v_step_finished) / 1000, 3), 'OK', CURRENT_TIMESTAMP(6));

        SET v_batch_finished = NOW(6);
        INSERT INTO performance_log (
            run_id, batch_name, step_no, procedure_name, started_at, finished_at, duration_ms, status, error_message, created_at
        )
        VALUES (
            v_run_id,
            'run_erp_scheduled_batch',
            9999,
            '__batch_total__',
            v_batch_started,
            v_batch_finished,
            ROUND(TIMESTAMPDIFF(MICROSECOND, v_batch_started, v_batch_finished) / 1000, 3),
            'OK',
            NULL,
            CURRENT_TIMESTAMP(6)
        );

        DO RELEASE_LOCK('run_erp_scheduled_batch');
    END IF;
END$$

DELIMITER ;

-- Интервал: каждые 30 секунд (начиная с момента активации события).
CREATE EVENT ev_erp_run_batch
ON SCHEDULE EVERY 30 SECOND
ON COMPLETION PRESERVE
ENABLE
COMMENT 'ERP: пакет процедур run_erp_scheduled_batch'
DO CALL run_erp_scheduled_batch();
