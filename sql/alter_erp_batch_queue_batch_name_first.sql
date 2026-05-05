-- Перемещает главное поле erp_batch_queue.batch_name в начало таблицы.
-- Тип и ограничения поля сохраняются.

ALTER TABLE `erp_batch_queue`
    MODIFY COLUMN `batch_name` varchar(128)
        CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci
        NOT NULL
        FIRST;
