-- Уточнение таблицы Documents для схемы "один документ = один файл".
-- Выполнить для уже созданной Documents. Если колонка/индекс уже есть,
-- соответствующую ошибку Duplicate column/key можно игнорировать.

ALTER TABLE `Documents`
    ADD COLUMN `file_name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL
        COMMENT 'Имя файла, которое пользователь должен положить в incoming'
        AFTER `Comment`;

ALTER TABLE `Documents`
    ADD COLUMN `file_path` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL
        COMMENT 'Кликабельная ссылка/UNC-путь на файл в file_vault'
        AFTER `file_name`;

ALTER TABLE `Documents`
    ADD COLUMN `file_status` enum('Ожидает файл','Файл найден','Ошибка') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'Ожидает файл'
        AFTER `file_path`;

ALTER TABLE `Documents`
    ADD COLUMN `file_error` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL
        AFTER `file_status`;

ALTER TABLE `Documents`
    ADD COLUMN `file_sha256` char(64) CHARACTER SET ascii COLLATE ascii_general_ci NULL
        AFTER `file_error`;

ALTER TABLE `Documents`
    ADD COLUMN `file_size_bytes` bigint unsigned NULL
        AFTER `file_sha256`;

ALTER TABLE `Documents`
    ADD COLUMN `file_uploaded_at` timestamp NULL DEFAULT NULL
        AFTER `file_size_bytes`;

ALTER TABLE `Documents`
    ADD KEY `idx_documents_file_name` (`file_name`);

ALTER TABLE `Documents`
    ADD KEY `idx_documents_file_status` (`file_status`);
