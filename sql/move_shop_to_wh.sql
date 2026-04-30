-- move_shop_to_wh: возврат с цеха на склад (move, вернуть на склад из финальных статусов цеха).
-- Блокировка: lock_return_shopfloor_to_warehouse
-- Чтение Main: MAX+COUNT — без NOT FOUND при отсутствии строки (общий handler с курсором).
-- Меняются только счётчики Main, Status_* и аудит в Transactions; прочие реквизиты строк не трогаем.

DELIMITER $$

DROP PROCEDURE IF EXISTS move_shop_to_wh$$

CREATE PROCEDURE move_shop_to_wh()
BEGIN
    DECLARE done INT DEFAULT 0;
    DECLARE v_lock_ok INT DEFAULT 0;

    DECLARE v_tx_id INT;
    DECLARE v_erp_id VARCHAR(255);
    DECLARE v_qty BIGINT;
    DECLARE v_sf BIGINT DEFAULT NULL;
    DECLARE v_main_cnt INT DEFAULT 0;

    DECLARE cur CURSOR FOR
        SELECT t.id, t.ERP_ID, COALESCE(t.Quantity_of_parts_total, 0)
        FROM `Transactions` t
        WHERE t.type = 'move'
          AND t.Status_transaction = 'В ожидании'
          AND t.Order_wh = 'Принято на склад'
          AND t.Order_prod = 'Вернуть на склад'
          AND t.Status_warehouse IN ('Утилизация', 'Сборка', 'Упаковка', 'Доработка')
        ORDER BY t.id;

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        IF v_lock_ok = 1 THEN
            DO RELEASE_LOCK('lock_return_shopfloor_to_warehouse');
        END IF;
        RESIGNAL;
    END;

    SELECT GET_LOCK('lock_return_shopfloor_to_warehouse', 0) INTO v_lock_ok;

    IF v_lock_ok = 1 THEN
        START TRANSACTION;

        OPEN cur;

        read_loop: LOOP
            FETCH cur INTO v_tx_id, v_erp_id, v_qty;
            IF done = 1 THEN
                LEAVE read_loop;
            END IF;

            IF v_qty <= 0 THEN
                ITERATE read_loop;
            END IF;

            SELECT
                COALESCE(MAX(m.Quantity_on_shopfloor), 0),
                COUNT(*)
            INTO v_sf, v_main_cnt
            FROM `Main` m
            WHERE m.ERP_ID = v_erp_id;

            IF v_main_cnt = 0 OR v_sf < v_qty THEN
                ITERATE read_loop;
            END IF;

            UPDATE `Main` m
               SET m.Quantity_on_shopfloor = m.Quantity_on_shopfloor - v_qty,
                   m.Quantity_in_warehouse = m.Quantity_in_warehouse + v_qty,
                   m.updated_at              = CURRENT_TIMESTAMP,
                   m.updated_by              = 'return_shopfloor_to_warehouse'
             WHERE m.ERP_ID = v_erp_id;

            UPDATE `Transactions` t
               SET t.Status_warehouse   = 'Норма',
                   t.Status_transaction = 'Исполнено',
                   t.updated_at         = CURRENT_TIMESTAMP,
                   t.updated_by         = CASE
                                              WHEN `updated_by` IS NULL OR TRIM(COALESCE(`updated_by`, '')) = '' THEN 'move_shop_to_wh'
                                              ELSE CONCAT(`updated_by`, '; ', 'move_shop_to_wh')
                                         END
             WHERE t.id = v_tx_id;
        END LOOP;

        CLOSE cur;

        COMMIT;
        DO RELEASE_LOCK('lock_return_shopfloor_to_warehouse');
    END IF;
END$$

DELIMITER ;
