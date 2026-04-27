-- Перемещение Status_warehouse сразу после Status_transaction.
--
-- Пустой результат у SELECT с DATABASE() бывает, если в phpMyAdmin не выбрана БД слева
-- (DATABASE() возвращает NULL — условие TABLE_SCHEMA = DATABASE() ни с чем не совпадает).
--
-- ========== 0) Диагностика: найти схему и точное имя таблицы ==========
-- Выполните отдельно:

SELECT DATABASE() AS current_database;

SELECT
  c.TABLE_SCHEMA,
  c.TABLE_NAME,
  c.COLUMN_NAME,
  c.ORDINAL_POSITION
FROM INFORMATION_SCHEMA.COLUMNS c
WHERE c.COLUMN_NAME IN ('Status_warehouse', 'Status_transaction')
  AND c.TABLE_SCHEMA NOT IN ('mysql', 'information_schema', 'performance_schema', 'sys')
ORDER BY c.TABLE_SCHEMA, c.TABLE_NAME, c.COLUMN_NAME;

-- Если таблица называется не `Transactions`, а например `transactions`, смотрите колонку TABLE_NAME ниже.

-- ========== 1) Генерация ALTER: подставьте имя базы вместо your_database ==========
-- Замените your_database на схему из шага 0 (колонка TABLE_SCHEMA).

SET SESSION group_concat_max_len = 8192;

SELECT CONCAT(
  'ALTER TABLE `', REPLACE(c.TABLE_SCHEMA, '`', '``'), '`.`', REPLACE(c.TABLE_NAME, '`', '``'), '` MODIFY COLUMN `Status_warehouse` ',
  c.COLUMN_TYPE,
  IF(c.IS_NULLABLE = 'NO', ' NOT NULL', ' NULL'),
  CASE
    WHEN c.COLUMN_DEFAULT IS NULL AND c.IS_NULLABLE = 'YES'
         AND c.COLUMN_TYPE NOT LIKE 'timestamp%' AND c.COLUMN_TYPE NOT LIKE 'datetime%'
      THEN ' DEFAULT NULL'
    WHEN c.COLUMN_DEFAULT IS NULL THEN ''
    WHEN c.COLUMN_TYPE LIKE 'varchar%' OR c.COLUMN_TYPE LIKE 'char%' OR c.COLUMN_TYPE LIKE 'varbinary%' OR c.COLUMN_TYPE LIKE 'binary%'
      THEN CONCAT(' DEFAULT ', QUOTE(c.COLUMN_DEFAULT))
    WHEN c.COLUMN_TYPE LIKE 'enum%' OR c.COLUMN_TYPE LIKE 'set%'
      THEN CONCAT(' DEFAULT ', QUOTE(c.COLUMN_DEFAULT))
    ELSE CONCAT(' DEFAULT ', c.COLUMN_DEFAULT)
  END,
  IF(c.EXTRA = '', '', CONCAT(' ', c.EXTRA)),
  IF(c.COLUMN_COMMENT = '', '', CONCAT(' COMMENT ', QUOTE(c.COLUMN_COMMENT))),
  ' AFTER `Status_transaction`;'
) AS run_this_statement
FROM INFORMATION_SCHEMA.COLUMNS c
WHERE c.TABLE_SCHEMA = 'your_database'
  AND c.TABLE_NAME = 'Transactions'
  AND c.COLUMN_NAME = 'Status_warehouse'
  AND EXISTS (
    SELECT 1
    FROM INFORMATION_SCHEMA.COLUMNS st
    WHERE st.TABLE_SCHEMA = c.TABLE_SCHEMA
      AND st.TABLE_NAME = c.TABLE_NAME
      AND st.COLUMN_NAME = 'Status_transaction'
  );

-- ========== 2) Если база уже выбрана в phpMyAdmin (слева кликнули на БД) ==========

SET SESSION group_concat_max_len = 8192;

SELECT CONCAT(
  'ALTER TABLE `', REPLACE(c.TABLE_SCHEMA, '`', '``'), '`.`', REPLACE(c.TABLE_NAME, '`', '``'), '` MODIFY COLUMN `Status_warehouse` ',
  c.COLUMN_TYPE,
  IF(c.IS_NULLABLE = 'NO', ' NOT NULL', ' NULL'),
  CASE
    WHEN c.COLUMN_DEFAULT IS NULL AND c.IS_NULLABLE = 'YES'
         AND c.COLUMN_TYPE NOT LIKE 'timestamp%' AND c.COLUMN_TYPE NOT LIKE 'datetime%'
      THEN ' DEFAULT NULL'
    WHEN c.COLUMN_DEFAULT IS NULL THEN ''
    WHEN c.COLUMN_TYPE LIKE 'varchar%' OR c.COLUMN_TYPE LIKE 'char%' OR c.COLUMN_TYPE LIKE 'varbinary%' OR c.COLUMN_TYPE LIKE 'binary%'
      THEN CONCAT(' DEFAULT ', QUOTE(c.COLUMN_DEFAULT))
    WHEN c.COLUMN_TYPE LIKE 'enum%' OR c.COLUMN_TYPE LIKE 'set%'
      THEN CONCAT(' DEFAULT ', QUOTE(c.COLUMN_DEFAULT))
    ELSE CONCAT(' DEFAULT ', c.COLUMN_DEFAULT)
  END,
  IF(c.EXTRA = '', '', CONCAT(' ', c.EXTRA)),
  IF(c.COLUMN_COMMENT = '', '', CONCAT(' COMMENT ', QUOTE(c.COLUMN_COMMENT))),
  ' AFTER `Status_transaction`;'
) AS run_this_statement
FROM INFORMATION_SCHEMA.COLUMNS c
WHERE c.TABLE_SCHEMA = DATABASE()
  AND c.TABLE_SCHEMA IS NOT NULL
  AND c.TABLE_NAME = 'Transactions'
  AND c.COLUMN_NAME = 'Status_warehouse'
  AND EXISTS (
    SELECT 1
    FROM INFORMATION_SCHEMA.COLUMNS st
    WHERE st.TABLE_SCHEMA = c.TABLE_SCHEMA
      AND st.TABLE_NAME = c.TABLE_NAME
      AND st.COLUMN_NAME = 'Status_transaction'
  );

-- ========== 3) Таблица в нижнем регистре (Linux) ==========
-- Выполните, если в шаге 0 видно TABLE_NAME = transactions

SET SESSION group_concat_max_len = 8192;

SELECT CONCAT(
  'ALTER TABLE `', REPLACE(c.TABLE_SCHEMA, '`', '``'), '`.`', REPLACE(c.TABLE_NAME, '`', '``'), '` MODIFY COLUMN `Status_warehouse` ',
  c.COLUMN_TYPE,
  IF(c.IS_NULLABLE = 'NO', ' NOT NULL', ' NULL'),
  CASE
    WHEN c.COLUMN_DEFAULT IS NULL AND c.IS_NULLABLE = 'YES'
         AND c.COLUMN_TYPE NOT LIKE 'timestamp%' AND c.COLUMN_TYPE NOT LIKE 'datetime%'
      THEN ' DEFAULT NULL'
    WHEN c.COLUMN_DEFAULT IS NULL THEN ''
    WHEN c.COLUMN_TYPE LIKE 'varchar%' OR c.COLUMN_TYPE LIKE 'char%' OR c.COLUMN_TYPE LIKE 'varbinary%' OR c.COLUMN_TYPE LIKE 'binary%'
      THEN CONCAT(' DEFAULT ', QUOTE(c.COLUMN_DEFAULT))
    WHEN c.COLUMN_TYPE LIKE 'enum%' OR c.COLUMN_TYPE LIKE 'set%'
      THEN CONCAT(' DEFAULT ', QUOTE(c.COLUMN_DEFAULT))
    ELSE CONCAT(' DEFAULT ', c.COLUMN_DEFAULT)
  END,
  IF(c.EXTRA = '', '', CONCAT(' ', c.EXTRA)),
  IF(c.COLUMN_COMMENT = '', '', CONCAT(' COMMENT ', QUOTE(c.COLUMN_COMMENT))),
  ' AFTER `Status_transaction`;'
) AS run_this_statement
FROM INFORMATION_SCHEMA.COLUMNS c
WHERE c.TABLE_SCHEMA = 'your_database'
  AND c.TABLE_NAME = 'transactions'
  AND c.COLUMN_NAME = 'Status_warehouse';
