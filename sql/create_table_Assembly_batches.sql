-- Реестр сборочных партий. Заполняется отдельной процедурой.

CREATE TABLE IF NOT EXISTS `Assembly_batches` (
    `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    `created_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    `created_by` VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
    `updated_by` VARCHAR(2000) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
    `Assembly_batch_id` VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
    `Assembly_batch_name` TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
    `Assembly_batch_status` ENUM(
        'Нет спецификации',
        'Ожидает определения',
        'В закупке/изготовлении',
        'В комплектации',
        'В сборке',
        'Готов'
    ) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT NULL,
    `Assembly_batch_priority` INT NULL DEFAULT NULL,
    `Project` TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
    `Advanced_group` TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
    `Supplied_component_number` VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT NULL,
    `Target_assembly` TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
    `Comments` TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_assembly_batches_batch_id` (`Assembly_batch_id`),
    KEY `idx_assembly_batches_supplied_component_number` (`Supplied_component_number`),
    KEY `idx_assembly_batches_status_priority` (`Assembly_batch_status`, `Assembly_batch_priority`),
    KEY `idx_assembly_batches_project` (`Project`(255)),
    KEY `idx_assembly_batches_target_assembly` (`Target_assembly`(255)),
    KEY `idx_assembly_batches_advanced_group` (`Advanced_group`(255)),
    KEY `idx_assembly_batches_updated_at` (`updated_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
