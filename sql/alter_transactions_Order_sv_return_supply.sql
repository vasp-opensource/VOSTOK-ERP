-- Transactions.Order_sv: добавить распоряжение супервизора для возврата отрицательной change-строки в контур закупки/изготовления.
-- Выполнить на существующей БД, где колонка Order_sv уже создана.

ALTER TABLE `Transactions`
    MODIFY COLUMN `Order_sv` ENUM(
            'разбить',
            'забраковать',
            'отменить',
            'доработать запас',
            'вернуть в закупку/изготовление',
            'заменить со склада',
            'заменить и восполнить'
        ) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT NULL;
