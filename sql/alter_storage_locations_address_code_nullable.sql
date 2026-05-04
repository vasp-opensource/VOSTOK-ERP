-- Фикс для NocoDB: поле Cells.address_code заполняется триггером MySQL,
-- но NocoDB не даёт создать строку, если видит NOT NULL без ручного значения.
-- Разрешаем NULL на уровне формы; триггеры bi/bu_cells_address_code всё равно
-- заполняют address_code перед INSERT/UPDATE.

ALTER TABLE `Cells`
    MODIFY COLUMN `address_code` varchar(64)
        CHARACTER SET ascii COLLATE ascii_general_ci
        NULL DEFAULT NULL
        COMMENT 'Заполняется триггером; NULL разрешён, чтобы NocoDB не требовал ручной ввод';
