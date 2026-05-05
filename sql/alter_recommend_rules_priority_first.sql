-- Перемещает главное поле recommend_rules.priority в начало таблицы.
-- Тип и комментарий поля сохраняются.

ALTER TABLE `recommend_rules`
    MODIFY COLUMN `priority` int
        NOT NULL
        COMMENT 'Приоритет применения правил и условий'
        FIRST;
