-- Планировщик вызова bot_call каждые 37 секунд.
-- Перед использованием убедитесь, что event_scheduler включен:
--   SET GLOBAL event_scheduler = ON;

DROP EVENT IF EXISTS ev_bot_call_37s;

CREATE EVENT ev_bot_call_37s
ON SCHEDULE EVERY 37 SECOND
ON COMPLETION PRESERVE
ENABLE
COMMENT 'BOT: вызов bot_call каждые 37 секунд'
DO CALL bot_call();
