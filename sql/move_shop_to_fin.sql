-- move_shop_to_fin: закрытие move склад→брак / отгрузка / изделие после комплектации на цех.
-- Отбор: Status_warehouse и пары Order_prod + Order_OTK по цели; списание с Quantity_on_shopfloor
-- в Main: брак → Quantity_of_losses; отгрузка → Quantity_shipped; изделие → Quantity_implemented
-- (в ТЗ иногда: Quantity_loss / Quantity_finised — здесь используются фактические имена колонок Main).
-- Транзакция: Status_transaction = Исполнено; Status_warehouse без изменения.
-- Блокировка: lock_move_shop_to_fin
-- Чтение Main: MAX+COUNT — без NOT FOUND при отсутствии строки (общий handler с курсором).

DELIMITER $$

DROP PROCEDURE IF EXISTS move_shop_to_fin$$

CREATE PROCEDURE move_shop_to_fin()
BEGIN
    DECLARE done INT DEFAULT 0;
    DECLARE v_lock_ok INT DEFAULT 0;

    DECLARE v_tx_id INT;
    DECLARE v_erp_id VARCHAR(255);
    DECLARE v_qty BIGINT;
    DECLARE v_where_to VARCHAR(32);
    DECLARE v_sf BIGINT DEFAULT NULL;
    DECLARE v_main_cnt INT DEFAULT 0;

    DECLARE cur CURSOR FOR
        SELECT t.id, t.ERP_ID, COALESCE(t.Quantity_of_parts_total, 0), t.where_to
        FROM `Transactions` t
        WHERE t.type = 'move'
          AND t.where_from = 'склад'
          AND t.where_to IN ('брак', 'отгрузка', 'изделие')
          AND t.Status_transaction = 'В ожидании'
          AND (
              (t.where_to = 'брак'
               AND t.Status_warehouse = 'Утилизация'
               AND t.Order_prod = 'Забраковать'
               AND t.Order_OTK = 'Забраковано')
              OR
              (t.where_to = 'отгрузка'
               AND t.Status_warehouse = 'Упаковка'
               AND t.Order_prod = 'Отгружено'
               AND t.Order_OTK = 'Принято')
              OR
              (t.where_to = 'изделие'
               AND t.Status_warehouse = 'Сборка'
               AND t.Order_prod = 'Изготовлено'
               AND t.Order_OTK = 'Принято')
          )
        ORDER BY t.ERP_ID, t.id;

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        IF v_lock_ok = 1 THEN
            DO RELEASE_LOCK('lock_move_shop_to_fin');
        END IF;
        RESIGNAL;
    END;

    SELECT GET_LOCK('lock_move_shop_to_fin', 0) INTO v_lock_ok;

    IF v_lock_ok = 1 THEN
        START TRANSACTION;

        OPEN cur;

        read_loop: LOOP
            FETCH cur INTO v_tx_id, v_erp_id, v_qty, v_where_to;
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
                   m.Quantity_of_losses    = m.Quantity_of_losses + IF(v_where_to = 'брак', v_qty, 0),
                   m.Quantity_shipped      = m.Quantity_shipped + IF(v_where_to = 'отгрузка', v_qty, 0),
                   m.Quantity_implemented  = m.Quantity_implemented + IF(v_where_to = 'изделие', v_qty, 0),
                   m.updated_at            = CURRENT_TIMESTAMP,
                  m.updated_by            = 'move_shop_to_fin'
             WHERE m.ERP_ID = v_erp_id;

            UPDATE `Transactions` t
               SET t.Status_transaction = 'Исполнено',
                   t.updated_at         = CURRENT_TIMESTAMP,
                  t.updated_by         = CASE
                                            WHEN t.updated_by IS NULL OR TRIM(COALESCE(t.updated_by, '')) = '' THEN 'move_shop_to_fin'
                                            ELSE CONCAT(t.updated_by, '; ', 'move_shop_to_fin')
                                         END
             WHERE t.id = v_tx_id;
        END LOOP;

        CLOSE cur;

        COMMIT;
        DO RELEASE_LOCK('lock_move_shop_to_fin');
    END IF;
END$$

DELIMITER ;
