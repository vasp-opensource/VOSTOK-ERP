-- Колонка происхождения номенклатуры (отдельно от Order_purch и др.).
-- Выполните один раз на БД до вызова процедур, которые задают Transactions.Source.

ALTER TABLE `Transactions`
ADD COLUMN `Source` ENUM('Покупное', 'Собственное производство') NULL DEFAULT NULL
AFTER `Address`;
