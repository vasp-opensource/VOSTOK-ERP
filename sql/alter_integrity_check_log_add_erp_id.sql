-- Однократно для уже созданной таблицы integrity_check_log.
-- Если колонка/индекс уже есть, ошибку duplicate можно игнорировать.

ALTER TABLE `integrity_check_log`
    ADD COLUMN `ERP_ID` VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL AFTER `created_at`;

ALTER TABLE `integrity_check_log`
    ADD INDEX `idx_integrity_check_log_erp_id` (`ERP_ID`);
