-- Однократное добавление колонок Status в Main и Transactions (если нужны в NocoDB).
-- Текущая процедура ch_purch_to_wh их не использует — после ALTER при необходимости
-- добавьте в финальный UPDATE: INNER JOIN Main m … SET t.`Status` = m.`Status`.
--
-- Если колонка уже есть — не выполняйте соответствующий ALTER.

ALTER TABLE `Main`
    ADD COLUMN `Status` VARCHAR(255) NULL COMMENT 'Статус карточки номенклатуры' AFTER `changed_by`;

ALTER TABLE `Transactions`
    ADD COLUMN `Status` VARCHAR(255) NULL COMMENT 'Снимок Main.Status при закрытии транзакции' AFTER `changed_by`;
