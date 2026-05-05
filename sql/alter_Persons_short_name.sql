-- Persons.Short_name: автоматическое сокращенное имя в формате "Фамилия И.О.".
-- Выполнить на существующей БД, где таблица Persons уже создана.

ALTER TABLE `Persons`
    ADD COLUMN `Short_name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci
        GENERATED ALWAYS AS (
            TRIM(CONCAT(
                TRIM(`Surname`),
                CASE
                    WHEN CONCAT(
                        CASE WHEN NULLIF(TRIM(COALESCE(`First_name`, '')), '') IS NULL THEN '' ELSE CONCAT(LEFT(TRIM(`First_name`), 1), '.') END,
                        CASE WHEN NULLIF(TRIM(COALESCE(`Patronym`, '')), '') IS NULL THEN '' ELSE CONCAT(LEFT(TRIM(`Patronym`), 1), '.') END
                    ) = '' THEN ''
                    ELSE CONCAT(
                        ' ',
                        CASE WHEN NULLIF(TRIM(COALESCE(`First_name`, '')), '') IS NULL THEN '' ELSE CONCAT(LEFT(TRIM(`First_name`), 1), '.') END,
                        CASE WHEN NULLIF(TRIM(COALESCE(`Patronym`, '')), '') IS NULL THEN '' ELSE CONCAT(LEFT(TRIM(`Patronym`), 1), '.') END
                    )
                END
            ))
        ) STORED
        COMMENT 'Автоматически: Фамилия И.О.'
        AFTER `Patronym`;

ALTER TABLE `Persons`
    ADD KEY `idx_persons_short_name` (`Short_name`);
