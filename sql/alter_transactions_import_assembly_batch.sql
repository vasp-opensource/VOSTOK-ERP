-- Поля сборочной партии для планирования комплектации и сборочного производства.
-- Выполнить до деплоя процедур, копирующих полный набор реквизитов Transactions/Import.

ALTER TABLE `Transactions`
  ADD COLUMN `Assembly_batch_id` VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT NULL
    AFTER `Components_quantity_in_assembly`,
  ADD COLUMN `Assembly_batch_name` TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL
    AFTER `Assembly_batch_id`,
  ADD COLUMN `Assembly_batch_status` ENUM(
      'Нет спецификации',
      'Ожидает определения',
      'В закупке/изготовлении',
      'В комплектации',
      'В сборке',
      'Готов'
    ) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT NULL
    AFTER `Assembly_batch_name`,
  ADD COLUMN `Assembly_batch_priority` INT NULL DEFAULT NULL
    AFTER `Assembly_batch_status`;

ALTER TABLE `Import`
  ADD COLUMN `Assembly_batch_id` VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT NULL
    AFTER `Components_quantity_in_assembly`,
  ADD COLUMN `Assembly_batch_name` TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL
    AFTER `Assembly_batch_id`,
  ADD COLUMN `Assembly_batch_status` ENUM(
      'Нет спецификации',
      'Ожидает определения',
      'В закупке/изготовлении',
      'В комплектации',
      'В сборке',
      'Готов'
    ) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT NULL
    AFTER `Assembly_batch_name`,
  ADD COLUMN `Assembly_batch_priority` INT NULL DEFAULT NULL
    AFTER `Assembly_batch_status`;
