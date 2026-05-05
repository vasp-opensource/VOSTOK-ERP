-- Перемещает главное поле Cells.address_code в начало таблицы.
-- Тип и ограничения поля сохраняются.

ALTER TABLE `Cells`
    MODIFY COLUMN `address_code` varchar(64)
        CHARACTER SET ascii COLLATE ascii_general_ci
        NULL DEFAULT NULL
        COMMENT 'Заполняется триггером; NULL разрешён, чтобы NocoDB не требовал ручной ввод'
        FIRST;
