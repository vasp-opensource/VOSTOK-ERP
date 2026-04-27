-- Смок-тест move_wh_to_shopfloor: объединение двух change по ERP_ID + Advanced_group.
-- Ожидание после CALL:
--   • старые change: Status_transaction = «Заменено», в linked_transaction дописан id суммарной новой строки;
--   • новая строка change: Quantity_change = сумма, в linked_transaction дописан собственный id;
--
-- Запускать на копии БД или после бэкапа. Перед CALL не должно быть «висячих» move
-- (type=move, where_from=склад, where_to IN (брак,отгрузка,изделие), Status_warehouse=Новая, Order_wh IS NULL),
-- иначе они тоже попадут в курсор процедуры.
--
-- Настройте префикс теста (уникальный в вашей базе):
SET @test_erp = '__TEST_MWTSF_001__';
SET @ag       = 'AG_TEST_MERGE_01';

-- --- Подготовка: карточка Main (если у вас NOT NULL на других полях — дополните INSERT) ---
INSERT INTO `Main` (
    ERP_ID,
    Quantity_in_warehouse,
    created_at,
    updated_at,
    created_by,
    updated_by
)
SELECT
    @test_erp,
    0,
    NOW(),
    NOW(),
    'test_mwtsf',
    'test_mwtsf'
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM `Main` m WHERE m.ERP_ID = @test_erp);

-- --- Две строки change для merge (один ERP_ID, один Advanced_group, Order_purch «Ожидание закупки») ---
INSERT INTO `Transactions` (
    ERP_ID,
    type,
    where_from,
    where_to,
    Quantity_of_parts_total,
    Quantity_change,
    Status_transaction,
    Order_purch,
    Advanced_group,
    Status_warehouse,
    Source,
    created_at,
    updated_at,
    created_by,
    updated_by
)
VALUES (
    @test_erp,
    'change',
    'внешний',
    'склад',
    0,
    10,
    'В ожидании',
    'Ожидание закупки',
    @ag,
    'Новая',
    'Покупное',
    NOW(),
    NOW(),
    'test_mwtsf',
    'test_mwtsf'
);

SET @ch_id_a = LAST_INSERT_ID();

INSERT INTO `Transactions` (
    ERP_ID,
    type,
    where_from,
    where_to,
    Quantity_of_parts_total,
    Quantity_change,
    Status_transaction,
    Order_purch,
    Advanced_group,
    Status_warehouse,
    Source,
    created_at,
    updated_at,
    created_by,
    updated_by
)
VALUES (
    @test_erp,
    'change',
    'внешний',
    'склад',
    0,
    25,
    'В ожидании',
    'Ожидание закупки',
    @ag,
    'Новая',
    'Покупное',
    NOW(),
    NOW(),
    'test_mwtsf',
    'test_mwtsf'
);

SET @ch_id_b = LAST_INSERT_ID();

SELECT 'До вызова: созданы change id' AS step, @ch_id_a AS id_a, @ch_id_b AS id_b;

-- CALL move_wh_to_shopfloor(); -- исключено из вызовов

-- Суммарная строка (создаётся первой в merge-цикле)
SET @sum_id = (
    SELECT t.id
    FROM `Transactions` t
    WHERE t.ERP_ID = @test_erp
      AND t.type = 'change'
      AND t.created_by = 'move_wh_to_shopfloor'
    ORDER BY t.id DESC
    LIMIT 1
);

-- Родители: Заменено, linked содержит id суммарной (цепочка через «; »)
SELECT
    'После: родительские строки' AS step,
    t.id,
    t.Quantity_change,
    t.Status_transaction,
    t.linked_transaction,
    (FIND_IN_SET(CAST(@sum_id AS CHAR), REPLACE(IFNULL(t.linked_transaction, ''), '; ', ',')) > 0) AS linked_ok_points_to_sum
FROM `Transactions` t
WHERE t.id IN (@ch_id_a, @ch_id_b);

-- Суммарная: linked содержит себя, количество 35
SELECT
    'После: суммарная строка' AS step,
    t.id,
    t.ERP_ID,
    t.Quantity_change,
    t.linked_transaction,
    (FIND_IN_SET(CAST(t.id AS CHAR), REPLACE(IFNULL(t.linked_transaction, ''), '; ', ',')) > 0) AS linked_ok_self,
    (t.Quantity_change = 35) AS qty_ok
FROM `Transactions` t
WHERE t.id = @sum_id;

-- --- Очистка теста (раскомментируйте после проверки) ---
-- DELETE FROM `Transactions` WHERE ERP_ID = @test_erp;
-- DELETE FROM `Main` WHERE ERP_ID = @test_erp;
