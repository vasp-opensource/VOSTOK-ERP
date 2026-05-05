-- prework_address: дозаполняет пустой Transactions.Address из назначенной ячейки Main.
-- Источник адреса: Main.cell_id -> Cells.address_code; Main.Address используется как текстовый fallback.

DROP PROCEDURE IF EXISTS prework_address;

DELIMITER $$

CREATE PROCEDURE prework_address()
BEGIN
    DECLARE v_lock_ok INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        IF v_lock_ok = 1 THEN
            DO RELEASE_LOCK('lock_prework_address');
        END IF;
        RESIGNAL;
    END;

    SELECT GET_LOCK('lock_prework_address', 0) INTO v_lock_ok;

    IF COALESCE(v_lock_ok, 0) <> 1 THEN
        SET @erp_batch_blocked_message = 'Blocked: lock_prework_address lock is already held';
    ELSE
        UPDATE `Transactions` t
        INNER JOIN `Main` m
          ON m.`ERP_ID` COLLATE utf8mb4_unicode_ci = t.`ERP_ID` COLLATE utf8mb4_unicode_ci
        INNER JOIN `Cells` c
          ON c.`id` = m.`cell_id`
        SET
            t.`Address` = COALESCE(NULLIF(TRIM(COALESCE(c.`address_code`, '')), ''), NULLIF(TRIM(COALESCE(m.`Address`, '')), '')),
            t.`updated_by` = CASE
                WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'prework_address'
                ELSE CONCAT(t.`updated_by`, '; ', 'prework_address')
            END,
            t.`updated_at` = CURRENT_TIMESTAMP
        WHERE (t.`Address` IS NULL OR TRIM(COALESCE(t.`Address`, '')) = '')
          AND m.`cell_id` IS NOT NULL
          AND COALESCE(NULLIF(TRIM(COALESCE(c.`address_code`, '')), ''), NULLIF(TRIM(COALESCE(m.`Address`, '')), '')) IS NOT NULL;

        DO RELEASE_LOCK('lock_prework_address');
    END IF;
END$$

DELIMITER ;
