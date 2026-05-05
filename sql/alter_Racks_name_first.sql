-- Перемещает главное поле Racks.name в начало таблицы.
-- Тип и NULL-режим поля сохраняются.

ALTER TABLE `Racks`
    MODIFY COLUMN `name` varchar(255)
        CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci
        NULL
        FIRST;
