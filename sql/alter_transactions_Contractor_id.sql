-- Связь Transactions с Contractors для выбора контрагента из справочника.
-- Если колонка/индекс/constraint уже есть, соответствующую ошибку можно игнорировать.

ALTER TABLE `Transactions`
    ADD COLUMN `Contractor_id` int unsigned NULL
        AFTER `Supplier`;

ALTER TABLE `Transactions`
    ADD KEY `idx_transactions_contractor_id` (`Contractor_id`);

ALTER TABLE `Transactions`
    ADD CONSTRAINT `fk_transactions_contractor`
        FOREIGN KEY (`Contractor_id`) REFERENCES `Contractors` (`id`)
        ON UPDATE CASCADE
        ON DELETE SET NULL;
