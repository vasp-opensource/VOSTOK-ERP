-- Контрагенты, банковские реквизиты и контактные лица.
-- Модель:
--   Transactions.Contractor_id -> Contractors.id (многие транзакции к одному контрагенту)
--   Contractors -> Contractor_bank_accounts -> Banks (несколько счетов контрагента)
--   Contractors <-> Persons через Contractor_persons, с должностью в связующей таблице.

CREATE TABLE IF NOT EXISTS `Banks` (
    `BIK` char(9) CHARACTER SET ascii COLLATE ascii_general_ci NOT NULL
        COMMENT 'БИК участника расчетов, ED807 BIC',
    `Bank_name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL
        COMMENT 'Наименование участника, ED807 ParticipantInfo.NameP',
    `Short_name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
    `Korrespond_account_number` char(20) CHARACTER SET ascii COLLATE ascii_general_ci NULL
        COMMENT 'Корреспондентский счет, ED807 Accounts.Account',
    `Account_status` varchar(16) CHARACTER SET ascii COLLATE ascii_general_ci NULL
        COMMENT 'Статус счета из ED807 Accounts.AccountStatus',
    `Account_type` varchar(16) CHARACTER SET ascii COLLATE ascii_general_ci NULL
        COMMENT 'Тип счета из ED807 Accounts.RegulationAccountType',
    `Participant_status` varchar(16) CHARACTER SET ascii COLLATE ascii_general_ci NULL
        COMMENT 'Статус участника из ED807 ParticipantInfo.ParticipantStatus',
    `Participant_type` varchar(16) CHARACTER SET ascii COLLATE ascii_general_ci NULL
        COMMENT 'Тип участника из ED807 ParticipantInfo.PtType',
    `Services` varchar(64) CHARACTER SET ascii COLLATE ascii_general_ci NULL
        COMMENT 'Сервисы участника из ED807 ParticipantInfo.Srvcs',
    `Exchange_type` varchar(16) CHARACTER SET ascii COLLATE ascii_general_ci NULL
        COMMENT 'Тип обмена из ED807 ParticipantInfo.XchType',
    `Region` varchar(16) CHARACTER SET ascii COLLATE ascii_general_ci NULL
        COMMENT 'Регион из ED807 ParticipantInfo.Rgn',
    `City` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL
        COMMENT 'Населенный пункт из ED807 ParticipantInfo.Nnp',
    `Address` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL
        COMMENT 'Адрес из ED807 ParticipantInfo.Adr',
    `Registration_number` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL
        COMMENT 'Регистрационный номер кредитной организации из ED807 ParticipantInfo.RegN',
    `Parent_BIK` char(9) CHARACTER SET ascii COLLATE ascii_general_ci NULL
        COMMENT 'БИК головного участника из ED807 ParticipantInfo.PrntBIC',
    `Date_in` date NULL
        COMMENT 'Дата включения участника из ED807 ParticipantInfo.DateIn',
    `Source_updated_at` date NULL
        COMMENT 'Дата справочника ED807',
    `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`BIK`),
    KEY `idx_banks_bank_name` (`Bank_name`),
    KEY `idx_banks_corr_account` (`Korrespond_account_number`),
    KEY `idx_banks_parent_bik` (`Parent_BIK`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `Contractors` (
    `id` int unsigned NOT NULL AUTO_INCREMENT,
    `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    `Short_name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
    `Full_name` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
    `Email` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
    `Tel_no` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
    `Post_address` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
    `INN` varchar(12) CHARACTER SET ascii COLLATE ascii_general_ci NULL,
    `KPP` char(9) CHARACTER SET ascii COLLATE ascii_general_ci NULL,
    `OGRN` varchar(15) CHARACTER SET ascii COLLATE ascii_general_ci NULL,
    `Director` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL
        COMMENT 'Руководитель из внешнего справочника, например DaData.management.name',
    `Status` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL
        COMMENT 'Статус контрагента из внешнего справочника, например DaData/FNS',
    `Registration_date` date NULL,
    `Liquidation_date` date NULL,
    `Source_name` varchar(64) CHARACTER SET ascii COLLATE ascii_general_ci NULL,
    `Source_updated_at` timestamp NULL DEFAULT NULL,
    `Comment` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_contractors_inn_kpp` (`INN`, `KPP`),
    KEY `idx_contractors_short_name` (`Short_name`),
    KEY `idx_contractors_director` (`Director`),
    KEY `idx_contractors_inn` (`INN`),
    KEY `idx_contractors_ogrn` (`OGRN`),
    KEY `idx_contractors_status` (`Status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `Contractor_bank_accounts` (
    `id` int unsigned NOT NULL AUTO_INCREMENT,
    `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    `Contractor_id` int unsigned NOT NULL,
    `BIK` char(9) CHARACTER SET ascii COLLATE ascii_general_ci NOT NULL,
    `Bank_account_number` char(20) CHARACTER SET ascii COLLATE ascii_general_ci NOT NULL,
    `Account_priority` enum('Основной','Дополнительный') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'Дополнительный',
    `Is_active` tinyint(1) NOT NULL DEFAULT 1,
    `Comment` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_contractor_bank_account` (`Contractor_id`, `Bank_account_number`),
    KEY `idx_contractor_bank_accounts_contractor` (`Contractor_id`),
    KEY `idx_contractor_bank_accounts_bik` (`BIK`),
    KEY `idx_contractor_bank_accounts_priority` (`Contractor_id`, `Account_priority`),
    CONSTRAINT `fk_contractor_bank_accounts_contractor`
        FOREIGN KEY (`Contractor_id`) REFERENCES `Contractors` (`id`)
        ON UPDATE CASCADE
        ON DELETE CASCADE,
    CONSTRAINT `fk_contractor_bank_accounts_bank`
        FOREIGN KEY (`BIK`) REFERENCES `Banks` (`BIK`)
        ON UPDATE CASCADE
        ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `Persons` (
    `id` int unsigned NOT NULL AUTO_INCREMENT,
    `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    `Surname` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
    `First_name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
    `Patronym` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
    `Short_name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci
        GENERATED ALWAYS AS (
            TRIM(CONCAT(
                TRIM(`Surname`),
                CASE
                    WHEN CONCAT(
                        CASE WHEN NULLIF(TRIM(COALESCE(`First_name`, '')), '') IS NULL THEN '' ELSE CONCAT(LEFT(TRIM(`First_name`), 1), '.') END,
                        CASE WHEN NULLIF(TRIM(COALESCE(`Patronym`, '')), '') IS NULL THEN '' ELSE CONCAT(LEFT(TRIM(`Patronym`), 1), '.') END
                    ) = '' THEN ''
                    ELSE CONCAT(
                        ' ',
                        CASE WHEN NULLIF(TRIM(COALESCE(`First_name`, '')), '') IS NULL THEN '' ELSE CONCAT(LEFT(TRIM(`First_name`), 1), '.') END,
                        CASE WHEN NULLIF(TRIM(COALESCE(`Patronym`, '')), '') IS NULL THEN '' ELSE CONCAT(LEFT(TRIM(`Patronym`), 1), '.') END
                    )
                END
            ))
        ) STORED
        COMMENT 'Автоматически: Фамилия И.О.',
    `Email` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
    `Tel_no` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
    `Comment` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
    PRIMARY KEY (`id`),
    KEY `idx_persons_short_name` (`Short_name`),
    KEY `idx_persons_name` (`Surname`, `First_name`, `Patronym`),
    KEY `idx_persons_email` (`Email`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `Contractor_persons` (
    `Contractor_id` int unsigned NOT NULL,
    `Person_id` int unsigned NOT NULL,
    `Position` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
    `Is_primary` tinyint(1) NOT NULL DEFAULT 0,
    `Comment` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
    `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`Contractor_id`, `Person_id`),
    KEY `idx_contractor_persons_person` (`Person_id`),
    KEY `idx_contractor_persons_position` (`Position`),
    CONSTRAINT `fk_contractor_persons_contractor`
        FOREIGN KEY (`Contractor_id`) REFERENCES `Contractors` (`id`)
        ON UPDATE CASCADE
        ON DELETE CASCADE,
    CONSTRAINT `fk_contractor_persons_person`
        FOREIGN KEY (`Person_id`) REFERENCES `Persons` (`id`)
        ON UPDATE CASCADE
        ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
