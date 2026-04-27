DROP EVENT IF EXISTS ev_cleanup_performance_log_30d;

CREATE EVENT ev_cleanup_performance_log_30d
ON SCHEDULE EVERY 1 DAY
STARTS (TIMESTAMP(CURRENT_DATE + INTERVAL 1 DAY, '01:05:00'))
ON COMPLETION PRESERVE
ENABLE
COMMENT 'Ежедневная очистка performance_log старше 30 дней'
DO CALL cleanup_performance_log_30d();
