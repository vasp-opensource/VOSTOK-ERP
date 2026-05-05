-- Перемещает главное поле Documents.Document_no в начало таблицы.
-- Тип и ограничения поля сохраняются.

ALTER TABLE `Documents`
    MODIFY COLUMN `Document_no` varchar(255)
        CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci
        NOT NULL
        FIRST;
