-- return_kit_to_wh: возврат из комплектации на склад по move-строкам.
-- Вход:
--   type='move', where_from='склад', where_to in ('брак','отгрузка','изделие','комплектация'),
--   Status_transaction='В ожидании',
--   Status_warehouse='Комплектация',
--   Order_wh='Принято на склад'.
--
-- Выход:
--   1) Для входящих строк: Status_warehouse='Дефицит склада', Order_prod=NULL.
--   2) Для Main по тем же ERP_ID:
--      Quantity_in_kitting -= SUM(Quantity_of_parts_total),
--      Quantity_in_warehouse += SUM(Quantity_of_parts_total).
--   3) Для всех строк Transactions с тем же ERP_ID:
--      если Status_transaction='В ожидании' и Status_warehouse='Ожидание поставки',
--      то Status_warehouse='Дефицит склада'.

DELIMITER $$

DROP PROCEDURE IF EXISTS return_kit_to_wh$$

CREATE PROCEDURE return_kit_to_wh()
BEGIN
    DECLARE v_lock_ok INT DEFAULT 0;
    DECLARE v_updated_by_max INT DEFAULT 2000;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        IF v_lock_ok = 1 THEN
            DO RELEASE_LOCK('lock_return_kit_to_wh');
        END IF;
        RESIGNAL;
    END;

    SELECT COALESCE(c.CHARACTER_MAXIMUM_LENGTH, 2000)
      INTO v_updated_by_max
    FROM information_schema.COLUMNS c
    WHERE c.TABLE_SCHEMA = DATABASE()
      AND c.TABLE_NAME = 'Transactions'
      AND c.COLUMN_NAME = 'updated_by'
    LIMIT 1;

    SELECT GET_LOCK('lock_return_kit_to_wh', 0) INTO v_lock_ok;

    IF v_lock_ok = 1 THEN
        START TRANSACTION;

        DROP TEMPORARY TABLE IF EXISTS tmp_return_kit_pick;
        CREATE TEMPORARY TABLE tmp_return_kit_pick (
            id INT UNSIGNED NOT NULL PRIMARY KEY,
            ERP_ID VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
            qty_return BIGINT NOT NULL,
            KEY idx_return_kit_erp_id (ERP_ID)
        );

        INSERT INTO tmp_return_kit_pick (id, ERP_ID, qty_return)
        SELECT
            t.id,
            CAST(t.ERP_ID AS CHAR CHARACTER SET utf8mb4) COLLATE utf8mb4_unicode_ci,
            COALESCE(t.Quantity_of_parts_total, 0) AS qty_return
        FROM `Transactions` t
        WHERE t.type = 'move'
          AND t.where_from = 'склад'
          AND t.where_to IN ('брак', 'отгрузка', 'изделие', 'комплектация')
          AND t.Status_transaction = 'В ожидании'
          AND t.Status_warehouse = 'Комплектация'
          AND t.Order_wh = 'Принято на склад';

        UPDATE `Transactions` t
        INNER JOIN tmp_return_kit_pick x ON x.id = t.id
        SET
            t.Status_warehouse = 'Дефицит склада',
            t.Order_prod = NULL,
            t.updated_by = CASE
                               WHEN t.updated_by IS NULL OR TRIM(COALESCE(t.updated_by, '')) = '' THEN 'return_kit_to_wh'
                               ELSE LEFT(CONCAT(t.updated_by, '; ', 'return_kit_to_wh'), v_updated_by_max)
                           END,
            t.updated_at = CURRENT_TIMESTAMP;

        DROP TEMPORARY TABLE IF EXISTS tmp_return_kit_agg;
        CREATE TEMPORARY TABLE tmp_return_kit_agg AS
        SELECT
            x.ERP_ID,
            SUM(COALESCE(x.qty_return, 0)) AS qty_total
        FROM tmp_return_kit_pick x
        GROUP BY x.ERP_ID;

        UPDATE `Main` m
        INNER JOIN tmp_return_kit_agg a ON a.ERP_ID COLLATE utf8mb4_unicode_ci = m.ERP_ID COLLATE utf8mb4_unicode_ci
        SET
            m.Quantity_in_kitting = COALESCE(m.Quantity_in_kitting, 0) - COALESCE(a.qty_total, 0),
            m.Quantity_in_warehouse = COALESCE(m.Quantity_in_warehouse, 0) + COALESCE(a.qty_total, 0),
            m.updated_by = 'return_kit_to_wh',
            m.updated_at = CURRENT_TIMESTAMP;

        UPDATE `Transactions` t
        INNER JOIN (
            SELECT DISTINCT ERP_ID
            FROM tmp_return_kit_pick
        ) e ON e.ERP_ID COLLATE utf8mb4_unicode_ci = t.ERP_ID COLLATE utf8mb4_unicode_ci
        SET
            t.Status_warehouse = 'Дефицит склада',
            t.updated_by = CASE
                               WHEN t.updated_by IS NULL OR TRIM(COALESCE(t.updated_by, '')) = '' THEN 'return_kit_to_wh'
                               ELSE LEFT(CONCAT(t.updated_by, '; ', 'return_kit_to_wh'), v_updated_by_max)
                           END,
            t.updated_at = CURRENT_TIMESTAMP
        WHERE t.Status_transaction = 'В ожидании'
          AND t.Status_warehouse = 'Ожидание поставки';

        DROP TEMPORARY TABLE IF EXISTS tmp_return_kit_agg;
        DROP TEMPORARY TABLE IF EXISTS tmp_return_kit_pick;

        COMMIT;
        DO RELEASE_LOCK('lock_return_kit_to_wh');
    END IF;
END$$

DELIMITER ;
