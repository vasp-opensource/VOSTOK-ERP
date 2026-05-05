-- Перемещает главное поле Warehouses.name в начало таблицы.
-- Тип и NULL-режим поля сохраняются.

ALTER TABLE `Warehouses`
    MODIFY COLUMN `name` varchar(255)
        CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci
        NULL
        FIRST;
