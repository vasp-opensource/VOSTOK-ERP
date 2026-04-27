-- Происхождение номенклатуры на уровне карточки Main (согласование с Transactions.Source при оприходовании).
-- Выполните после появления колонки Source в Transactions (см. alter_transactions_Source.sql).

ALTER TABLE `Main`
ADD COLUMN `Source` ENUM('Покупное', 'Собственное производство') NULL DEFAULT NULL
AFTER `Address`;
