-- Добавляет размер файла в байтах для уже созданной таблицы Documents.
-- Если колонка уже есть, ошибку Duplicate column name можно игнорировать.

ALTER TABLE `Documents`
    ADD COLUMN `file_size_bytes` bigint unsigned NULL
        AFTER `file_sha256`;
