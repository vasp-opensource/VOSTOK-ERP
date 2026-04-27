-- Планировщик метрик ERP: ежедневный запуск collect_erp_metrics().
-- Перед использованием: SET GLOBAL event_scheduler = ON;

SET @old_time_zone = @@session.time_zone;
SET time_zone = '+03:00';

DROP EVENT IF EXISTS ev_collect_erp_metrics;

CREATE EVENT ev_collect_erp_metrics
ON SCHEDULE EVERY 1 DAY
STARTS (TIMESTAMP(CURRENT_DATE + INTERVAL 1 DAY, '00:05:00'))
ON COMPLETION PRESERVE
ENABLE
COMMENT 'ERP: ежедневный сбор метрик в erp_metrics'
DO CALL collect_erp_metrics();

SET time_zone = @old_time_zone;
