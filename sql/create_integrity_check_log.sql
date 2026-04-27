-- Лог проверки целостности данных (заполняется процедурами валидации).

CREATE TABLE IF NOT EXISTS `integrity_check_log` (
    `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `ERP_ID` VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
    `procedure_name` VARCHAR(255) NOT NULL,
    `error_message` TEXT NOT NULL,
    PRIMARY KEY (`id`),
    KEY `idx_integrity_check_log_erp_id` (`ERP_ID`),
    KEY `idx_integrity_check_log_created_at` (`created_at`),
    KEY `idx_integrity_check_log_procedure_name` (`procedure_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
