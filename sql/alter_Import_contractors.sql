-- Import: реквизиты контрагента для автоматической связи импортируемых Transactions с Contractors.
-- В Excel/NocoDB достаточно заполнить Contractor_INN; для юрлиц желательно также Contractor_KPP.

ALTER TABLE `Import`
    ADD COLUMN `Contractor_INN` varchar(12) CHARACTER SET ascii COLLATE ascii_general_ci NULL
        AFTER `Supplier`,
    ADD COLUMN `Contractor_KPP` char(9) CHARACTER SET ascii COLLATE ascii_general_ci NULL
        AFTER `Contractor_INN`,
    ADD KEY `idx_import_contractor_inn_kpp` (`Contractor_INN`, `Contractor_KPP`);
