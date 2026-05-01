-- Исторически: третье значение ENUM «Разные» для расхождений Main/Transactions.
-- Текущие ch_purch_to_wh / ch_ownprod_to_wh не записывают «Разные» в Source.
-- Выполняйте только если колонка Source уже создана с двумя значениями и нужен ENUM с «Разные» (например, для старых данных или других процедур).

ALTER TABLE `Transactions`
MODIFY COLUMN `Source` ENUM('Покупное', 'Собственное производство', 'Разные') NULL DEFAULT NULL;
