-- Однократно, если колонок ещё нет (ошибку «Duplicate column» можно игнорировать).

ALTER TABLE `Transactions`
    ADD COLUMN `Supplier` TEXT NULL AFTER `Cost_total_rub`;

ALTER TABLE `Transactions`
    ADD COLUMN `Price_of_single_unit` DOUBLE NULL AFTER `Supplier`;

ALTER TABLE `Transactions`
    ADD COLUMN `Location` TEXT NULL AFTER `Price_of_single_unit`;
