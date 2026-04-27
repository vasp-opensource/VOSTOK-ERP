DROP PROCEDURE IF EXISTS cleanup_performance_log_30d;

CREATE PROCEDURE cleanup_performance_log_30d()
BEGIN
    DELETE FROM `performance_log`
    WHERE `created_at` < (NOW(6) - INTERVAL 30 DAY);
END;
