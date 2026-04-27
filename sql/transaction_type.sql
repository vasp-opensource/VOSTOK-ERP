-- transaction_type: нормализация типов/количеств (склад→отгрузка/брак → move + комплектация; move склад→изделие; обнуление total для change).
-- Пустые строки (оба количества 0) → Status_transaction «Отменено» до прочих шагов.
-- Логика совпадает с шагами 0–2 бывш. sp_normalize_transactions.
-- Назначения «брак» и «отгрузка» — всегда move, не change.
--
-- 3) Для change + внешний→склад + склад «Новая», только если Order_purch IS NULL: ищем другую строку с тем же ERP_ID (первая по MIN(id)).
--    С её Order_purch: «Собственное производство» → то же; «В закупке» или «Оплачено» → «В закупке». Иначе не меняем.
--    Если Order_purch уже задан (не NULL и не пустая строка) — не трогаем; при простановке — updated_by = «transaction_type».

DELIMITER $$

DROP PROCEDURE IF EXISTS transaction_type$$

CREATE PROCEDURE transaction_type()
BEGIN
  START TRANSACTION;

  /* Пустая заявка: нет ни изменения, ни «постоянного» количества — отмена */
  UPDATE Transactions t
  SET t.Status_transaction = 'Отменено',
      t.updated_by = CASE
                        WHEN t.updated_by IS NULL OR TRIM(COALESCE(t.updated_by, '')) = '' THEN 'transaction_type'
                        ELSE CONCAT(t.updated_by, '; ', 'transaction_type')
                     END,
      t.updated_at = CURRENT_TIMESTAMP
  WHERE COALESCE(t.Quantity_change, 0) = 0
    AND COALESCE(t.Quantity_of_parts_total, 0) = 0
    AND (t.Status_transaction IS NULL OR t.Status_transaction = 'В ожидании');

  UPDATE Transactions t
  SET t.type = 'move',
      t.Order_wh = 'В комплектации',
      t.Order_purch = NULL,
      t.updated_by = CASE
                        WHEN t.updated_by IS NULL OR TRIM(COALESCE(t.updated_by, '')) = '' THEN 'transaction_type'
                        ELSE CONCAT(t.updated_by, '; ', 'transaction_type')
                     END,
      t.updated_at = CURRENT_TIMESTAMP
  WHERE t.where_from = 'склад'
    AND t.where_to IN ('отгрузка', 'брак')
    AND t.Quantity_of_parts_total > 0
    AND IFNULL(t.Quantity_change, 0) = 0;

  UPDATE Main m
  INNER JOIN Transactions t ON t.ERP_ID = m.ERP_ID
  SET m.Quantity_in_warehouse = m.Quantity_in_warehouse
      - LEAST(t.Quantity_of_parts_total, GREATEST(m.Quantity_in_warehouse, 0)),
      m.Quantity_in_kitting = COALESCE(m.Quantity_in_kitting, 0)
      + LEAST(t.Quantity_of_parts_total, GREATEST(m.Quantity_in_warehouse, 0)),
      m.updated_at = CURRENT_TIMESTAMP
  WHERE t.where_from = 'склад'
    AND t.where_to IN ('отгрузка', 'брак')
    AND t.Quantity_of_parts_total > 0
    AND IFNULL(t.Quantity_change, 0) = 0
    AND t.type = 'move'
    AND m.Quantity_in_warehouse > 0;

  -- 1) Нет изменения количества → move «склад → изделие». Строки с where_to «отгрузка» или «брак» не трогаем.
  UPDATE Transactions
  SET type = 'move',
      where_from = 'склад',
      where_to = 'изделие',
      Order_purch = NULL,
      updated_by = CASE
                     WHEN updated_by IS NULL OR TRIM(COALESCE(updated_by, '')) = '' THEN 'transaction_type'
                     ELSE CONCAT(updated_by, '; ', 'transaction_type')
                   END,
      updated_at = CURRENT_TIMESTAMP
  WHERE (Quantity_change IS NULL OR Quantity_change = 0)
    AND where_to NOT IN ('отгрузка', 'брак')
    AND NOT (Status_transaction <=> 'Отменено');

  -- 2) Для запросов на изменение обнуляем «постоянное» количество; исключаем строки шага 0.
  UPDATE Transactions
  SET Quantity_of_parts_total = 0,
      updated_by = CASE
                     WHEN updated_by IS NULL OR TRIM(COALESCE(updated_by, '')) = '' THEN 'transaction_type'
                     ELSE CONCAT(updated_by, '; ', 'transaction_type')
                   END,
      updated_at = CURRENT_TIMESTAMP
  WHERE type = 'change'
    AND NOT (Status_transaction <=> 'Отменено')
    AND NOT (
      where_from = 'склад'
      AND where_to IN ('отгрузка', 'брак', 'изделие')
      AND Quantity_of_parts_total > 0
      AND IFNULL(Quantity_change, 0) = 0
    );

  /* 3) Order_purch: change, внешний→склад, Новая — с первой по id другой записи с тем же ERP_ID */
  UPDATE `Transactions` t
  INNER JOIN (
    SELECT
      t2.`id` AS new_id,
      CASE
        WHEN p.`Order_purch` = 'Собственное производство' THEN 'Собственное производство'
        WHEN p.`Order_purch` IN ('В закупке', 'Оплачено') THEN 'В закупке'
      END AS new_order_purch
    FROM `Transactions` t2
    INNER JOIN (
      SELECT
        t3.`id` AS tid,
        MIN(p3.`id`) AS first_other_id
      FROM `Transactions` t3
      INNER JOIN `Transactions` p3
        ON p3.`ERP_ID` <=> t3.`ERP_ID`
       AND p3.`id` <> t3.`id`
      WHERE t3.`type` = 'change'
        AND t3.`where_from` = 'внешний'
        AND t3.`where_to` = 'склад'
        AND t3.`Status_warehouse` = 'Новая'
        AND t3.`ERP_ID` IS NOT NULL
        AND TRIM(IFNULL(t3.`ERP_ID`, '')) <> ''
      GROUP BY t3.`id`
    ) pick ON pick.`tid` = t2.`id`
    INNER JOIN `Transactions` p ON p.`id` = pick.`first_other_id`
  ) x ON t.`id` = x.`new_id`
  SET
    t.`Order_purch` = x.`new_order_purch`,
    t.`updated_by` = CASE
                        WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'transaction_type'
                        ELSE CONCAT(t.`updated_by`, '; ', 'transaction_type')
                     END,
    t.`updated_at`  = CURRENT_TIMESTAMP
  WHERE x.`new_order_purch` IS NOT NULL
    AND (t.`Order_purch` IS NULL OR TRIM(IFNULL(t.`Order_purch`, '')) = '');

  COMMIT;
END$$

DELIMITER ;
