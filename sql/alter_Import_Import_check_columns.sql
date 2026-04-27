-- Однократно для уже созданной таблицы Import (ошибку «Duplicate column» можно игнорировать).
--
-- Если колонка уже создана под именем Quantity_available, переименуйте:
-- ALTER TABLE `Import` RENAME COLUMN `Quantity_available` TO `Quantity_avaliable`;

ALTER TABLE `Import`
    ADD COLUMN `Quantity_avaliable` bigint NULL AFTER `Quantity_of_losses`;

-- Было tinyint(1): в import_check хранится величина «сколько можно отменить», не boolean.
ALTER TABLE `Import`
    MODIFY COLUMN `Cant_be_cancelled` bigint NOT NULL DEFAULT 0;

-- Было tinyint(1): хранится величина недостачи (например 1080 − 972), не 0/1.
ALTER TABLE `Import`
    MODIFY COLUMN `Needed_new` bigint NOT NULL DEFAULT 0;
