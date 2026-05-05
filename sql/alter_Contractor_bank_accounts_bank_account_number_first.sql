-- Перемещает главное поле Contractor_bank_accounts.Bank_account_number в начало таблицы.
-- Тип и ограничения поля сохраняются.

ALTER TABLE `Contractor_bank_accounts`
    MODIFY COLUMN `Bank_account_number` char(20)
        CHARACTER SET ascii COLLATE ascii_general_ci
        NOT NULL
        FIRST;
