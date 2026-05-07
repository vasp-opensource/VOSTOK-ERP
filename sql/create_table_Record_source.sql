-- Создать таблицу Record_source как структурную копию Transactions.
-- Копируются колонки, типы, индексы и значения AUTO_INCREMENT/DEFAULT (без данных).

CREATE TABLE IF NOT EXISTS `Record_source` LIKE `Transactions`;
<<<<<<< HEAD

ALTER TABLE `Record_source`
    ADD COLUMN `Contractor_INN` varchar(12) CHARACTER SET ascii COLLATE ascii_general_ci NULL
        AFTER `Supplier`,
    ADD COLUMN `Contractor_KPP` char(9) CHARACTER SET ascii COLLATE ascii_general_ci NULL
        AFTER `Contractor_INN`,
    ADD KEY `idx_record_source_contractor_inn_kpp` (`Contractor_INN`, `Contractor_KPP`);
=======
>>>>>>> b29be25 (fix: stabilize supervisor and import SQL workflows)
