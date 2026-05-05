-- Таблица Documents: карточки закрывающих/сопроводительных документов.
-- Один документ = один файл скана. Файл физически хранится вне MySQL,
-- в базе хранятся имя ожидаемого файла, ссылка на файл в file_vault и метаданные.

CREATE TABLE IF NOT EXISTS `Documents` (
    `id` int unsigned NOT NULL AUTO_INCREMENT,
    `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    `Document_no` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
    `Document_date` date NULL,
    `Document_name` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
    `Document_type` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
    `Contractor_id` int unsigned NOT NULL
        COMMENT 'Контрагент документа',
    `Comment` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
    `file_name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL
        COMMENT 'Имя файла, которое пользователь должен положить в incoming',
    `file_path` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL
        COMMENT 'Кликабельная ссылка/UNC-путь на файл в file_vault',
    `file_status` enum('Ожидает файл','Файл найден','Ошибка') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'Ожидает файл',
    `file_error` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
    `file_sha256` char(64) CHARACTER SET ascii COLLATE ascii_general_ci NULL,
    `file_size_bytes` bigint unsigned NULL,
    `file_uploaded_at` timestamp NULL DEFAULT NULL,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_documents_document_no_date` (`Document_no`, `Document_date`),
    KEY `idx_documents_contractor_id` (`Contractor_id`),
    KEY `idx_documents_file_name` (`file_name`),
    KEY `idx_documents_file_status` (`file_status`),
    CONSTRAINT `fk_documents_contractor`
        FOREIGN KEY (`Contractor_id`) REFERENCES `Contractors` (`id`)
        ON UPDATE CASCADE
        ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
