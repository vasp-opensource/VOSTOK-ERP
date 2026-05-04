-- Таблица Transactions: даты/документ, рекомендации, решения по складу, переделка; расширение ENUM.
-- Выполнить один раз на БД. Порядок ADD сохраняет цепочку AFTER.
-- Order_sv: в ТЗ «забраковать» перечислено дважды — в ENUM одно значение.

/* --- новые столбцы --- */

ALTER TABLE `Transactions`
    ADD COLUMN `Document_date` DATE NULL DEFAULT NULL
        COMMENT 'Дата закрывающего документа'
        AFTER `Document_no`;

ALTER TABLE `Transactions`
    ADD COLUMN `Recommend_purchprod` ENUM(
            'Уточнить кол-во в изготовлении',
            'Уточнить кол-во в закупке',
            'Уточнить ревизию в изготовлении',
            'Уточнить ревизию в закупке'
        ) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT NULL
        AFTER `Address`;

ALTER TABLE `Transactions`
    ADD COLUMN `Order_sv` ENUM(
            'разбить',
            'забраковать',
            'отменить',
            'доработать запас',
            'вернуть в закупку/изготовление',
            'заменить со склада',
            'заменить и восполнить'
        ) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT NULL
        AFTER `Order_OTK`;

ALTER TABLE `Transactions`
    ADD COLUMN `Recommend_wh` TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT NULL
        AFTER `Order_sv`;

ALTER TABLE `Transactions`
    ADD COLUMN `Quantity_ordered` BIGINT NOT NULL DEFAULT 0
        AFTER `Recommend_wh`;

ALTER TABLE `Transactions`
    ADD COLUMN `Replace_to` TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT NULL
        AFTER `Quantity_ordered`;

ALTER TABLE `Transactions`
    ADD COLUMN `Rework_to` TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT NULL
        AFTER `Replace_to`;

ALTER TABLE `Transactions`
    ADD COLUMN `Rework_from` TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT NULL
        AFTER `Rework_to`;

/* --- расширение ENUM (полные списки; «Комплектация» уже была, добавляем «Ожидает решения») --- */

ALTER TABLE `Transactions`
    MODIFY COLUMN `Status_warehouse` ENUM(
            'Норма',
            'Дефицит склада',
            'Ожидание закупки',
            'Ожидание изготовления',
            'Дефицит поставки',
            'Комплектация',
            'В закупке',
            'В изготовлении',
            'Новая',
            'Утилизация',
            'Сборка',
            'Упаковка',
            'Ожидание поставки',
            'Ожидает решения'
        ) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT NULL;

ALTER TABLE `Transactions`
    MODIFY COLUMN `where_to` ENUM(
            'закупка',
            'склад',
            'цех',
            'собственное производство',
            'отгрузка',
            'брак',
            'изделие',
            'доработка'
        ) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'закупка';
