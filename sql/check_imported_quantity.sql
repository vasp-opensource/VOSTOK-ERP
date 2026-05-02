-- check_imported_quantity: самостоятельная проверка согласованности Import и Transactions; нарушения пишутся в integrity_check_log.
-- Сверка: агрегаты по change (Status_transaction, created_by) vs SUM(Quantity_change) по Import при Status_import=«Импортировано».
-- Используются только количество и перечисленные статусы/метки; строки Transactions, созданные create_row, не участвуют.
-- Поля Main и новые реквизиты Transactions (документы, Order_*, Rework_*, …) в расчёте не участвуют.

DELIMITER $$

DROP PROCEDURE IF EXISTS check_imported_quantity$$

CREATE PROCEDURE check_imported_quantity()
proc: BEGIN
    DECLARE v_kernel_lock INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        DROP TEMPORARY TABLE IF EXISTS `tmp_import_integrity_candidates`;
        IF v_kernel_lock = 1 THEN
            DO RELEASE_LOCK('batch_kernel');
        END IF;
        RESIGNAL;
    END;

    SELECT GET_LOCK('batch_kernel', 0) INTO v_kernel_lock;


    IF COALESCE(v_kernel_lock, 0) <> 1 THEN

        SET @erp_batch_blocked_message = 'Blocked: batch_kernel lock is already held';

    END IF;

    IF COALESCE(v_kernel_lock, 0) <> 1 THEN
        LEAVE proc;
    END IF;

    DROP TEMPORARY TABLE IF EXISTS `tmp_import_integrity_candidates`;
    CREATE TEMPORARY TABLE `tmp_import_integrity_candidates` (
        `procedure_name` VARCHAR(255) NOT NULL,
        `ERP_ID` VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
        `error_message` TEXT NOT NULL
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

    INSERT INTO `tmp_import_integrity_candidates` (`procedure_name`, `ERP_ID`, `error_message`)
    SELECT
        'check_imported_quantity',
        b.`ERP_ID`,
        CONCAT(
            'Transactions vs Import (change): ERP_ID=', b.`ERP_ID`,
            ' tx_wait_exec=', COALESCE(twe.sum_wait_exec, 0),
            ' tx_replaced_abs=', COALESCE(tr.sum_replaced_abs, 0),
            ' tx_deficit_supply=', COALESCE(tds.sum_deficit_supply, 0),
            ' tx_cancelled_abs=', COALESCE(tc.sum_cancelled_abs, 0),
            ' tx_replacedID_dif=', COALESCE(trid.sum_replaced_id_dif, 0),
            ' tx_result=',
            COALESCE(twe.sum_wait_exec, 0)
            - COALESCE(tds.sum_deficit_supply, 0)
            - COALESCE(tc.sum_cancelled_abs, 0)
            - COALESCE(trid.sum_replaced_id_dif, 0),
            ' import_imported=', COALESCE(i.sum_imported, 0)
        )
    FROM (
        SELECT (`ERP_ID` COLLATE utf8mb4_unicode_ci) AS `ERP_ID`
        FROM `Transactions`
        WHERE `type` = 'change'
          AND COALESCE(`created_by`, '') <> 'create_row'
        UNION
        SELECT (`ERP_ID` COLLATE utf8mb4_unicode_ci) AS `ERP_ID`
        FROM `Import`
        WHERE `Status_import` = 'Импортировано'
    ) b
    LEFT JOIN (
        SELECT
            `ERP_ID`,
            SUM(COALESCE(`Quantity_change`, 0)) AS sum_wait_exec
        FROM `Transactions`
        WHERE `type` = 'change'
          AND `Status_transaction` IN ('В ожидании', 'Исполнено', 'Заменен ID')
          AND COALESCE(`created_by`, '') <> 'create_row'
        GROUP BY `ERP_ID`
    ) twe ON twe.`ERP_ID` COLLATE utf8mb4_unicode_ci = b.`ERP_ID` COLLATE utf8mb4_unicode_ci
    LEFT JOIN (
        SELECT
            `ERP_ID`,
            SUM(ABS(COALESCE(`Quantity_change`, 0))) AS sum_replaced_abs
        FROM `Transactions`
        WHERE `type` = 'change'
          AND `Status_transaction` IN ('Заменено', 'Заменен ID')
          AND COALESCE(`created_by`, '') <> 'create_row'
          AND (
               `created_by` IS NULL
            OR `created_by` <> 'deficit_supply'
          )
        GROUP BY `ERP_ID`
    ) tr ON tr.`ERP_ID` COLLATE utf8mb4_unicode_ci = b.`ERP_ID` COLLATE utf8mb4_unicode_ci
    LEFT JOIN (
        SELECT
            `ERP_ID`,
            SUM(COALESCE(`Quantity_change`, 0)) AS sum_deficit_supply
        FROM `Transactions`
        WHERE `type` = 'change'
          AND `Status_transaction` IN ('В ожидании', 'Исполнено', 'Заменено', 'Заменен ID')
          AND `created_by` = 'deficit_supply'
          AND COALESCE(`created_by`, '') <> 'create_row'
        GROUP BY `ERP_ID`
    ) tds ON tds.`ERP_ID` COLLATE utf8mb4_unicode_ci = b.`ERP_ID` COLLATE utf8mb4_unicode_ci
    LEFT JOIN (
        SELECT
            `ERP_ID`,
            SUM(ABS(COALESCE(`Quantity_change`, 0))) AS sum_cancelled_abs
        FROM `Transactions`
        WHERE `type` = 'change'
          AND `Status_transaction` = 'Отменено'
          AND COALESCE(`created_by`, '') <> 'create_row'
        GROUP BY `ERP_ID`
    ) tc ON tc.`ERP_ID` COLLATE utf8mb4_unicode_ci = b.`ERP_ID` COLLATE utf8mb4_unicode_ci
    LEFT JOIN (
        SELECT
            `ERP_ID`,
            SUM(COALESCE(`Quantity_change`, 0)) AS sum_replaced_id_dif
        FROM `Transactions`
        WHERE `type` = 'change'
          AND `Status_transaction` = 'Заменено'
          AND `created_by` = 'create_row'
        GROUP BY `ERP_ID`
    ) trid ON trid.`ERP_ID` COLLATE utf8mb4_unicode_ci = b.`ERP_ID` COLLATE utf8mb4_unicode_ci
    LEFT JOIN (
        SELECT
            `ERP_ID`,
            SUM(COALESCE(`Quantity_change`, 0)) AS sum_imported
        FROM `Import`
        WHERE `Status_import` = 'Импортировано'
        GROUP BY `ERP_ID`
    ) i ON i.`ERP_ID` COLLATE utf8mb4_unicode_ci = b.`ERP_ID` COLLATE utf8mb4_unicode_ci
    WHERE (
            COALESCE(twe.sum_wait_exec, 0)
            - COALESCE(tds.sum_deficit_supply, 0)
            - COALESCE(tc.sum_cancelled_abs, 0)
            - COALESCE(trid.sum_replaced_id_dif, 0)
          ) <> COALESCE(i.sum_imported, 0);

    INSERT INTO `integrity_check_log` (`procedure_name`, `ERP_ID`, `error_message`)
    SELECT DISTINCT
        c.`procedure_name`,
        c.`ERP_ID`,
        c.`error_message`
    FROM `tmp_import_integrity_candidates` c
    WHERE NOT EXISTS (
        SELECT 1
        FROM `integrity_check_log` l
        WHERE l.`procedure_name` = c.`procedure_name`
          AND (l.`ERP_ID` <=> c.`ERP_ID`)
          AND l.`error_message` = (c.`error_message` COLLATE utf8mb4_unicode_ci)
    );

    DROP TEMPORARY TABLE IF EXISTS `tmp_import_integrity_candidates`;
    DO RELEASE_LOCK('batch_kernel');
END$$

DELIMITER ;
