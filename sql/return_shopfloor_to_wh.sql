-- return_shopfloor_to_wh: обработка возврата на склад по move-строкам.
-- Новые реквизиты Transactions (документы, Recommend_*, Order_sv, Rework_*, …) не обновляются —
--   меняются только Status_warehouse, Order_prod, аудит и перечисленные счётчики Main.
-- Вход:
--   type='move', where_from='склад', where_to in ('брак','отгрузка','изделие'),
--   Status_transaction='В ожидании',
--   Status_warehouse in ('Утилизация','Сборка','Упаковка'),
--   Order_prod='Вернуть на склад',
--   Order_wh='Принято на склад'.
--
-- Выход:
--   1) Для входящих строк: Status_warehouse='Дефицит склада', Order_prod=NULL.
--   2) Для Main по тем же ERP_ID:
--      Quantity_on_shopfloor -= SUM(Quantity_of_parts_total),
--      Quantity_in_warehouse += SUM(Quantity_of_parts_total).
--   3) Для всех строк Transactions с тем же ERP_ID:
--      если Status_transaction='В ожидании' и Status_warehouse='Ожидание поставки',
--      то Status_warehouse='Дефицит склада'.

DELIMITER $$

DROP PROCEDURE IF EXISTS return_shopfloor_to_wh$$

CREATE PROCEDURE return_shopfloor_to_wh()
BEGIN
    DECLARE v_lock_ok INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        IF v_lock_ok = 1 THEN
            DO RELEASE_LOCK('lock_return_shopfloor_to_wh');
        END IF;
        RESIGNAL;
    END;

    SELECT GET_LOCK('lock_return_shopfloor_to_wh', 0) INTO v_lock_ok;


    IF COALESCE(v_lock_ok, 0) <> 1 THEN

        SET @erp_batch_blocked_message = 'Blocked: lock_return_shopfloor_to_wh lock is already held';

    END IF;


    IF COALESCE(v_lock_ok, 0) <> 1 THEN

        SET @erp_batch_blocked_message = 'Blocked: lock_return_shopfloor_to_wh lock is already held';

    END IF;

    IF v_lock_ok = 1 THEN
        START TRANSACTION;

        DROP TEMPORARY TABLE IF EXISTS tmp_return_shopfloor_pick;
        CREATE TEMPORARY TABLE tmp_return_shopfloor_pick (
            id INT UNSIGNED NOT NULL PRIMARY KEY,
            ERP_ID VARCHAR(255) NOT NULL,
            qty_return BIGINT NOT NULL
        );

        INSERT INTO tmp_return_shopfloor_pick (id, ERP_ID, qty_return)
        SELECT
            t.id,
            t.ERP_ID,
            COALESCE(t.Quantity_of_parts_total, 0) AS qty_return
        FROM `Transactions` t
        WHERE t.type = 'move'
          AND t.where_from = 'склад'
          AND t.where_to IN ('брак', 'отгрузка', 'изделие')
          AND t.Status_transaction = 'В ожидании'
          AND t.Status_warehouse IN ('Утилизация', 'Сборка', 'Упаковка')
          AND t.Order_prod = 'Вернуть на склад'
          AND t.Order_wh = 'Принято на склад';

        UPDATE `Transactions` t
        INNER JOIN tmp_return_shopfloor_pick x ON x.id = t.id
        SET
            t.Status_warehouse = 'Дефицит склада',
            t.Order_prod = NULL,
            t.updated_by = CASE
                               WHEN t.updated_by IS NULL OR TRIM(COALESCE(t.updated_by, '')) = '' THEN 'return_shopfloor_to_wh'
                               ELSE CONCAT(t.updated_by, '; ', 'return_shopfloor_to_wh')
                           END,
            t.updated_at = CURRENT_TIMESTAMP;

        DROP TEMPORARY TABLE IF EXISTS tmp_return_shopfloor_agg;
        CREATE TEMPORARY TABLE tmp_return_shopfloor_agg AS
        SELECT
            x.ERP_ID,
            SUM(COALESCE(x.qty_return, 0)) AS qty_total
        FROM tmp_return_shopfloor_pick x
        GROUP BY x.ERP_ID;

        UPDATE `Main` m
        INNER JOIN tmp_return_shopfloor_agg a ON a.ERP_ID = m.ERP_ID
        SET
            m.Quantity_on_shopfloor = COALESCE(m.Quantity_on_shopfloor, 0) - COALESCE(a.qty_total, 0),
            m.Quantity_in_warehouse = COALESCE(m.Quantity_in_warehouse, 0) + COALESCE(a.qty_total, 0),
            m.updated_by = 'return_shopfloor_to_wh',
            m.updated_at = CURRENT_TIMESTAMP;

        UPDATE `Transactions` t
        INNER JOIN (
            SELECT DISTINCT ERP_ID
            FROM tmp_return_shopfloor_pick
        ) e ON e.ERP_ID = t.ERP_ID
        SET
            t.Status_warehouse = 'Дефицит склада',
            t.updated_by = CASE
                               WHEN t.updated_by IS NULL OR TRIM(COALESCE(t.updated_by, '')) = '' THEN 'return_shopfloor_to_wh'
                               ELSE CONCAT(t.updated_by, '; ', 'return_shopfloor_to_wh')
                           END,
            t.updated_at = CURRENT_TIMESTAMP
        WHERE t.Status_transaction = 'В ожидании'
          AND t.Status_warehouse = 'Ожидание поставки';

        DROP TEMPORARY TABLE IF EXISTS tmp_return_shopfloor_agg;
        DROP TEMPORARY TABLE IF EXISTS tmp_return_shopfloor_pick;

        COMMIT;
        DO RELEASE_LOCK('lock_return_shopfloor_to_wh');
    END IF;
END$$

DELIMITER ;
