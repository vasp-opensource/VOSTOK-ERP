-- Создать таблицу Record_source как структурную копию Transactions.
-- Копируются колонки, типы, индексы и значения AUTO_INCREMENT/DEFAULT (без данных).

CREATE TABLE IF NOT EXISTS `Record_source` LIKE `Transactions`;
