-- Contractors: поля для автозаполнения карточки контрагента по ИНН из DaData/ФНС.
-- Выполнить на существующей БД, где таблица Contractors уже создана.

ALTER TABLE `Contractors`
    ADD COLUMN `Director` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL
        COMMENT 'Руководитель из внешнего справочника, например DaData.management.name'
        AFTER `OGRN`,
    ADD COLUMN `Status` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL
        COMMENT 'Статус контрагента из внешнего справочника, например DaData/FNS'
        AFTER `Director`,
    ADD COLUMN `Registration_date` date NULL
        AFTER `Status`,
    ADD COLUMN `Liquidation_date` date NULL
        AFTER `Registration_date`,
    ADD COLUMN `Source_name` varchar(64) CHARACTER SET ascii COLLATE ascii_general_ci NULL
        AFTER `Liquidation_date`,
    ADD COLUMN `Source_updated_at` timestamp NULL DEFAULT NULL
        AFTER `Source_name`,
    ADD KEY `idx_contractors_director` (`Director`),
    ADD KEY `idx_contractors_status` (`Status`);
