-- Тело процедуры sp_normalize_transactions (вставить в «Изменить» существующей процедуры между BEGIN и END).
-- Схема: PROJECT_CONTEXT.md.

  /* Пустая заявка: оба количества 0 → Отменено (согласовано с transaction_type) */
  UPDATE Transactions t
  SET t.Status_transaction = 'Отменено',
      t.updated_at = CURRENT_TIMESTAMP
  WHERE COALESCE(t.Quantity_change, 0) = 0
    AND COALESCE(t.Quantity_of_parts_total, 0) = 0
    AND (t.Status_transaction IS NULL OR t.Status_transaction = 'В ожидании');

  -- 0) Склад → отгрузка / брак: total > 0, изменения количества нет → тип move,
  --    Order_wh «В комплектации», Order_purch NULL; при остатке на складе — перенос в комплектацию.
  UPDATE Transactions t
  SET t.type = 'move',
      t.Order_wh = 'В комплектации',
      t.Order_purch = NULL,
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
      updated_at = CURRENT_TIMESTAMP
  WHERE (Quantity_change IS NULL OR Quantity_change = 0)
    AND where_to NOT IN ('отгрузка', 'брак')
    AND NOT (Status_transaction <=> 'Отменено');

  -- 2) Для запросов на изменение обнуляем «постоянное» количество; исключаем строки шага 0.
  UPDATE Transactions
  SET Quantity_of_parts_total = 0,
      updated_at = CURRENT_TIMESTAMP
  WHERE type = 'change'
    AND NOT (Status_transaction <=> 'Отменено')
    AND NOT (
      where_from = 'склад'
      AND where_to IN ('отгрузка', 'брак', 'изделие')
      AND Quantity_of_parts_total > 0
      AND IFNULL(Quantity_change, 0) = 0
    );
