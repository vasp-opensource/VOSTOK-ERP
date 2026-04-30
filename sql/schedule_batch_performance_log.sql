-- batch_performance_log: обслуживание performance-логов без отдельного логирования шагов.
-- Интервал запуска: каждые 2 минуты.
-- performance_log_collect будет создана отдельно.

DROP EVENT IF EXISTS ev_batch_performance_log_2m;

DROP PROCEDURE IF EXISTS batch_performance_log;

DELIMITER $$

CREATE PROCEDURE batch_performance_log()
BEGIN
    DECLARE v_batch_lock INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        IF v_batch_lock = 1 THEN
            DO RELEASE_LOCK('batch_performance_log');
        END IF;
        RESIGNAL;
    END;

    SELECT GET_LOCK('batch_performance_log', 0) INTO v_batch_lock;

    IF v_batch_lock = 1 THEN
        CALL performance_log_collect();
        CALL cleanup_performance_log_30d();

        DO RELEASE_LOCK('batch_performance_log');
    END IF;
END$$

DELIMITER ;

CREATE EVENT ev_batch_performance_log_2m
ON SCHEDULE EVERY 2 MINUTE
ON COMPLETION PRESERVE
ENABLE
COMMENT 'ERP: performance log maintenance every 2 minutes'
DO CALL batch_performance_log();
