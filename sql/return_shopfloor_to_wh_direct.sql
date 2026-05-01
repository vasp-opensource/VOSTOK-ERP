-- return_shopfloor_to_wh_direct: прямой возврат из цеха на склад по move-строкам.
-- Вход:
--   type='move', where_from='цех', where_to='склад',
--   Status_transaction='В ожидании',
--   Order_wh='Принято на склад', Order_prod='Вернуть на склад'.
-- Выход:
--   Main.Quantity_on_shopfloor -= SUM(Quantity_of_parts_total),
--   Main.Quantity_in_warehouse += SUM(Quantity_of_parts_total),
--   Transactions.Status_transaction='Исполнено'.

DELIMITER $$

DROP PROCEDURE IF EXISTS return_shopfloor_to_wh_direct$$

CREATE PROCEDURE return_shopfloor_to_wh_direct()
BEGIN
    DECLARE v_lock_ok INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        IF v_lock_ok = 1 THEN
            DO RELEASE_LOCK('lock_return_shopfloor_to_wh_direct');
        END IF;
        RESIGNAL;
    END;

    SELECT GET_LOCK('lock_return_shopfloor_to_wh_direct', 0) INTO v_lock_ok;

    IF v_lock_ok = 1 THEN
        START TRANSACTION;

        DROP TEMPORARY TABLE IF EXISTS tmp_return_shopfloor_direct_pick;
        CREATE TEMPORARY TABLE tmp_return_shopfloor_direct_pick (
            id BIGINT UNSIGNED NOT NULL PRIMARY KEY,
            ERP_ID VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
            qty_return DECIMAL(18,6) NOT NULL
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

        INSERT INTO tmp_return_shopfloor_direct_pick (id, ERP_ID, qty_return)
        SELECT
            t.id,
            t.ERP_ID,
            COALESCE(t.Quantity_of_parts_total, 0) AS qty_return
        FROM `Transactions` t
        WHERE t.type = 'move'
          AND t.where_from = 'цех'
          AND t.where_to = 'склад'
          AND t.Status_transaction = 'В ожидании'
          AND t.Order_wh = 'Принято на склад'
          AND t.Order_prod = 'Вернуть на склад'
          AND COALESCE(t.Quantity_of_parts_total, 0) > 0;

        DROP TEMPORARY TABLE IF EXISTS tmp_return_shopfloor_direct_agg;
        CREATE TEMPORARY TABLE tmp_return_shopfloor_direct_agg AS
        SELECT
            x.ERP_ID,
            SUM(COALESCE(x.qty_return, 0)) AS qty_total
        FROM tmp_return_shopfloor_direct_pick x
        GROUP BY x.ERP_ID;

        DROP TEMPORARY TABLE IF EXISTS tmp_return_shopfloor_direct_ready;
        CREATE TEMPORARY TABLE tmp_return_shopfloor_direct_ready AS
        SELECT
            a.ERP_ID,
            a.qty_total
        FROM tmp_return_shopfloor_direct_agg a
        INNER JOIN `Main` m
            ON m.ERP_ID COLLATE utf8mb4_unicode_ci = a.ERP_ID COLLATE utf8mb4_unicode_ci
        WHERE COALESCE(m.Quantity_on_shopfloor, 0) >= COALESCE(a.qty_total, 0);

        UPDATE `Main` m
        INNER JOIN tmp_return_shopfloor_direct_ready r
            ON r.ERP_ID COLLATE utf8mb4_unicode_ci = m.ERP_ID COLLATE utf8mb4_unicode_ci
        SET
            m.Quantity_on_shopfloor = COALESCE(m.Quantity_on_shopfloor, 0) - COALESCE(r.qty_total, 0),
            m.Quantity_in_warehouse = COALESCE(m.Quantity_in_warehouse, 0) + COALESCE(r.qty_total, 0),
            m.updated_by = 'return_shopfloor_to_wh_direct',
            m.updated_at = CURRENT_TIMESTAMP;

        UPDATE `Transactions` t
        INNER JOIN tmp_return_shopfloor_direct_pick x ON x.id = t.id
        INNER JOIN tmp_return_shopfloor_direct_ready r
            ON r.ERP_ID COLLATE utf8mb4_unicode_ci = x.ERP_ID COLLATE utf8mb4_unicode_ci
        SET
            t.Status_transaction = 'Исполнено',
            t.updated_by = CASE
                               WHEN t.updated_by IS NULL OR TRIM(COALESCE(t.updated_by, '')) = '' THEN 'return_shopfloor_to_wh_direct'
                               ELSE CONCAT(t.updated_by, '; ', 'return_shopfloor_to_wh_direct')
                           END,
            t.updated_at = CURRENT_TIMESTAMP;

        DROP TEMPORARY TABLE IF EXISTS tmp_return_shopfloor_direct_ready;
        DROP TEMPORARY TABLE IF EXISTS tmp_return_shopfloor_direct_agg;
        DROP TEMPORARY TABLE IF EXISTS tmp_return_shopfloor_direct_pick;

        COMMIT;
        DO RELEASE_LOCK('lock_return_shopfloor_to_wh_direct');
    END IF;
END$$

DELIMITER ;
