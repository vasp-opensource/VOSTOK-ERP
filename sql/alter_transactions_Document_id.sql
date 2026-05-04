-- Связь Transactions с Documents для выбора документа из выпадающего списка.
-- Если колонка/индекс/constraint уже есть, соответствующую ошибку можно игнорировать.

ALTER TABLE `Transactions`
    ADD COLUMN `Document_id` int unsigned NULL
        AFTER `Document_date`;

ALTER TABLE `Transactions`
    ADD KEY `idx_transactions_document_id` (`Document_id`);

ALTER TABLE `Transactions`
    ADD CONSTRAINT `fk_transactions_document`
        FOREIGN KEY (`Document_id`) REFERENCES `Documents` (`id`)
        ON UPDATE CASCADE
        ON DELETE SET NULL;
