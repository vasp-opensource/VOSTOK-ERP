-- Планировщик уведомлений о новых ошибках целостности.
-- Перед использованием убедитесь, что event_scheduler включен:
--   SET GLOBAL event_scheduler = ON;

DROP EVENT IF EXISTS ev_notify_integrity_email;

CREATE EVENT ev_notify_integrity_email
ON SCHEDULE EVERY 1 MINUTE
ON COMPLETION PRESERVE
ENABLE
COMMENT 'Notify new integrity_check_log rows by email outbox'
DO
  CALL notify_integrity_check_email('vpyzhyanov@vostk.su');
