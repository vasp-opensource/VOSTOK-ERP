-- VOSTOK_ERP: перенос столбца Status_warehouse сразу после Status_transaction.
-- Выполняет ALTER автоматически (полный текст не нужно копировать из результата SELECT).

USE `VOSTOK_ERP`;

SET SESSION group_concat_max_len = 8192;

SET @ddl := (
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
  )
  FROM INFORMATION_SCHEMA.COLUMNS c
  WHERE c.TABLE_SCHEMA = 'VOSTOK_ERP'
    AND c.TABLE_NAME = 'Transactions'
    AND c.COLUMN_NAME = 'Status_warehouse'
    AND EXISTS (
      SELECT 1
      FROM INFORMATION_SCHEMA.COLUMNS st
      WHERE st.TABLE_SCHEMA = c.TABLE_SCHEMA
        AND st.TABLE_NAME = c.TABLE_NAME
        AND st.COLUMN_NAME = 'Status_transaction'
    )
  LIMIT 1
);

SELECT IF(@ddl IS NULL,
  'Ошибка: не найден столбец — проверьте TABLE_NAME (Transactions / transactions)',
  @ddl) AS generated_or_error;

PREPARE stmt FROM @ddl;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;
