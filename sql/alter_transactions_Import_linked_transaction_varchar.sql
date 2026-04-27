-- Цепочка связанных id в одном поле (аналогично updated_by: значения через "; ").
-- Выполнить на БД до деплоя процедур с CONCAT/CASE по linked_transaction.

ALTER TABLE `Transactions`
  MODIFY COLUMN `linked_transaction` VARCHAR(1024) NULL DEFAULT NULL
    COMMENT 'Связанные id через ; (не перезаписывать — дописывать)';

ALTER TABLE `Import`
  MODIFY COLUMN `linked_transaction` VARCHAR(1024) NULL DEFAULT NULL
    COMMENT 'Связанные id через ; (не перезаписывать — дописывать)';
