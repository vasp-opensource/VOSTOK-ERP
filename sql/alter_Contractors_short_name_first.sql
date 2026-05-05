-- Перемещает главное поле Contractors.Short_name в начало таблицы.
-- Тип и NULL-режим поля сохраняются.

ALTER TABLE `Contractors`
    MODIFY COLUMN `Short_name` varchar(255)
        CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci
        NULL
        FIRST;
