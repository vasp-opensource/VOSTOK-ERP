-- Расширение журнала обработчиков updated_by.
-- Выполнить до запуска процедур, которые многократно дописывают имена обработчиков через "; ".

ALTER TABLE `Transactions`
  MODIFY COLUMN `updated_by` VARCHAR(2000) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT NULL;

ALTER TABLE `Import`
  MODIFY COLUMN `updated_by` VARCHAR(2000) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT NULL;
