DELIMITER $$

DROP PROCEDURE IF EXISTS replace_new$$

CREATE PROCEDURE replace_new(
    IN p_source_transaction_id BIGINT
)
proc: BEGIN
    DECLARE v_proc_name VARCHAR(64) DEFAULT 'replace_new';

    DECLARE v_source_id BIGINT DEFAULT NULL;
    DECLARE v_source_replace_to VARCHAR(255) DEFAULT NULL;
    DECLARE v_source_type VARCHAR(64) DEFAULT NULL;
    DECLARE v_source_where_from VARCHAR(128) DEFAULT NULL;
    DECLARE v_source_where_to VARCHAR(128) DEFAULT NULL;
    DECLARE v_source_qty_total DECIMAL(18,6) DEFAULT 0;
    DECLARE v_source_qty_change DECIMAL(18,6) DEFAULT 0;
    DECLARE v_source_status_transaction VARCHAR(64) DEFAULT NULL;
    DECLARE v_source_status_warehouse VARCHAR(64) DEFAULT NULL;
    DECLARE v_source_order_purch VARCHAR(128) DEFAULT NULL;
    DECLARE v_source_order_wh VARCHAR(128) DEFAULT NULL;
    DECLARE v_source_order_prod VARCHAR(128) DEFAULT NULL;
    DECLARE v_source_order_otk VARCHAR(128) DEFAULT NULL;

    DECLARE v_link_row_id BIGINT DEFAULT NULL;
    DECLARE v_new_id_move BIGINT DEFAULT NULL;
    DECLARE v_new_id_change BIGINT DEFAULT NULL;
    DECLARE v_created_from DATETIME(6) DEFAULT NULL;
    DECLARE v_link_token VARCHAR(64) DEFAULT NULL;

    SELECT
        t.id,
        t.Replace_to,
        t.type,
        t.where_from,
        t.where_to,
        t.Quantity_of_parts_total,
        t.Quantity_change,
        t.Status_transaction,
        t.Status_warehouse,
        t.Order_purch,
        t.Order_wh,
        t.Order_prod,
        t.Order_OTK
    INTO
        v_source_id,
        v_source_replace_to,
        v_source_type,
        v_source_where_from,
        v_source_where_to,
        v_source_qty_total,
        v_source_qty_change,
        v_source_status_transaction,
        v_source_status_warehouse,
        v_source_order_purch,
        v_source_order_wh,
        v_source_order_prod,
        v_source_order_otk
    FROM Transactions t
    WHERE t.id = p_source_transaction_id
    LIMIT 1;

    IF v_source_id IS NULL THEN
        LEAVE proc;
    END IF;

    IF v_source_replace_to IS NULL THEN
        UPDATE Transactions
        SET
            Order_sv = NULL,
            updated_at = NOW(),
            updated_by = CASE
                WHEN updated_by IS NULL OR updated_by = '' THEN CONCAT(v_proc_name, '; ')
                ELSE CONCAT(updated_by, v_proc_name, '; ')
            END
        WHERE id = v_source_id;
        LEAVE proc;
    END IF;

    SELECT t.id
    INTO v_link_row_id
    FROM Transactions t
    WHERE t.ERP_ID = v_source_replace_to
    ORDER BY t.created_at ASC, t.id ASC
    LIMIT 1;

    IF v_link_row_id IS NULL THEN
        UPDATE Transactions
        SET
            Order_sv = NULL,
            updated_at = NOW(),
            updated_by = CASE
                WHEN updated_by IS NULL OR updated_by = '' THEN CONCAT(v_proc_name, '; ')
                ELSE CONCAT(updated_by, v_proc_name, '; ')
            END
        WHERE id = v_source_id;
        LEAVE proc;
    END IF;

    SET v_link_token = CONCAT(v_source_id, '; ');
    SET v_created_from = NOW(6);

    IF v_source_type = 'move' THEN
        CALL create_row(
            v_source_id,
            'move',
            v_source_where_from,
            v_source_where_to,
            v_source_qty_total,
            0,
            v_source_status_transaction,
            v_source_status_warehouse,
            v_source_order_purch,
            v_source_order_wh,
            v_source_order_prod,
            v_source_order_otk,
            NULL
        );

        CALL create_row(
            v_source_id,
            'change',
            'внешний',
            'склад',
            0,
            COALESCE(v_source_qty_total, 0),
            'В ожидании',
            'Новая',
            NULL,
            NULL,
            NULL,
            NULL,
            NULL
        );

        SELECT t.id
        INTO v_new_id_move
        FROM Transactions t
        WHERE t.linked_transaction = v_source_id
          AND t.created_by = 'create_row'
          AND t.ERP_ID = v_source_replace_to
          AND t.type = 'move'
          AND t.created_at >= v_created_from
        ORDER BY t.created_at DESC, t.id DESC
        LIMIT 1;

        SELECT t.id
        INTO v_new_id_change
        FROM Transactions t
        WHERE t.linked_transaction = v_source_id
          AND t.created_by = 'create_row'
          AND t.ERP_ID = v_source_replace_to
          AND t.type = 'change'
          AND t.created_at >= v_created_from
        ORDER BY t.created_at DESC, t.id DESC
        LIMIT 1;

        UPDATE Transactions
        SET
            Status_transaction = 'Отменено',
            updated_at = NOW(),
            updated_by = CASE
                WHEN updated_by IS NULL OR updated_by = '' THEN CONCAT(v_proc_name, '; ')
                ELSE CONCAT(updated_by, v_proc_name, '; ')
            END
        WHERE id = v_source_id;

        UPDATE Transactions
        SET
            linked_transaction = CASE
                WHEN linked_transaction IS NULL OR linked_transaction = '' THEN v_link_token
                ELSE CONCAT(linked_transaction, v_link_token)
            END,
            updated_at = NOW(),
            updated_by = CASE
                WHEN updated_by IS NULL OR updated_by = '' THEN CONCAT(v_proc_name, '; ')
                ELSE CONCAT(updated_by, v_proc_name, '; ')
            END
        WHERE id IN (v_source_id, v_new_id_move, v_new_id_change);

    ELSEIF v_source_type = 'change'
       AND v_source_status_warehouse IN ('Новая', 'В закупке', 'В изготовлении') THEN

        CALL create_row(
            v_source_id,
            'change',
            'внешний',
            'склад',
            0,
            COALESCE(v_source_qty_change, 0),
            'В ожидании',
            'Новая',
            NULL,
            NULL,
            NULL,
            NULL,
            NULL
        );

        SELECT t.id
        INTO v_new_id_change
        FROM Transactions t
        WHERE t.linked_transaction = v_source_id
          AND t.created_by = 'create_row'
          AND t.ERP_ID = v_source_replace_to
          AND t.type = 'change'
          AND t.created_at >= v_created_from
        ORDER BY t.created_at DESC, t.id DESC
        LIMIT 1;

        UPDATE Transactions
        SET
            Status_transaction = 'Отменено',
            updated_at = NOW(),
            updated_by = CASE
                WHEN updated_by IS NULL OR updated_by = '' THEN CONCAT(v_proc_name, '; ')
                ELSE CONCAT(updated_by, v_proc_name, '; ')
            END
        WHERE id = v_source_id;

        UPDATE Transactions
        SET
            linked_transaction = CASE
                WHEN linked_transaction IS NULL OR linked_transaction = '' THEN v_link_token
                ELSE CONCAT(linked_transaction, v_link_token)
            END,
            updated_at = NOW(),
            updated_by = CASE
                WHEN updated_by IS NULL OR updated_by = '' THEN CONCAT(v_proc_name, '; ')
                ELSE CONCAT(updated_by, v_proc_name, '; ')
            END
        WHERE id IN (v_source_id, v_new_id_change);

    ELSE
        UPDATE Transactions
        SET
            Order_sv = NULL,
            updated_at = NOW(),
            updated_by = CASE
                WHEN updated_by IS NULL OR updated_by = '' THEN CONCAT(v_proc_name, '; ')
                ELSE CONCAT(updated_by, v_proc_name, '; ')
            END
        WHERE id = v_source_id;
    END IF;
END$$

DELIMITER ;
