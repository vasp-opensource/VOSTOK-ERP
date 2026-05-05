-- Record_source: ИНН/КПП контрагента для последующего копирования в Import и связи Transactions с Contractors.

ALTER TABLE `Record_source`
    ADD COLUMN `Contractor_INN` varchar(12) CHARACTER SET ascii COLLATE ascii_general_ci NULL
        AFTER `Supplier`,
    ADD COLUMN `Contractor_KPP` char(9) CHARACTER SET ascii COLLATE ascii_general_ci NULL
        AFTER `Contractor_INN`,
    ADD KEY `idx_record_source_contractor_inn_kpp` (`Contractor_INN`, `Contractor_KPP`);
