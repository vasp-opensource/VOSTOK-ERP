-- Однократно: колонка для копирования с исходной транзакции (если ещё не добавлена в БД).
-- При ошибке «Duplicate column» — колонка уже есть, скрипт можно не выполнять.

ALTER TABLE `Transactions`
    ADD COLUMN `Initial_doc_no` TEXT NULL AFTER `Zakaz_no`;
