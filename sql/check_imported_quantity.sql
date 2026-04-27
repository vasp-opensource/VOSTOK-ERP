-- check_imported_quantity: вызывается из check_data_integrity; пишет в tmp_integrity_candidates.
-- Сверка: агрегаты по change (Status_transaction, created_by) vs SUM(Quantity_change) по Import при Status_import=«Импортировано».
-- Используются только количество и перечисленные статусы/метки; поля Main и новые реквизиты Transactions (документы, Order_*, Rework_*, …) в расчёте не участвуют.

DELIMITER $$

CREATE PROCEDURE check_imported_quantity()
BEGIN
    /* Важно: процедура рассчитана на запуск ИЗ check_data_integrity,
       где уже создана tmp_integrity_candidates(procedure_name, ERP_ID, error_message). */

    INSERT INTO `tmp_integrity_candidates` (`procedure_name`, `ERP_ID`, `error_message`)
    SELECT
        'check_data_integrity',
        b.`ERP_ID`,
        CONCAT(
            'Transactions vs Import (change): ERP_ID=', b.`ERP_ID`,
            ' tx_wait_exec=', COALESCE(twe.sum_wait_exec, 0),
            ' tx_replaced_abs=', COALESCE(tr.sum_replaced_abs, 0),
            ' tx_deficit_supply=', COALESCE(tds.sum_deficit_supply, 0),
            ' tx_cancelled_abs=', COALESCE(tc.sum_cancelled_abs, 0),
            ' tx_result=',
            COALESCE(twe.sum_wait_exec, 0)
            - COALESCE(tds.sum_deficit_supply, 0)
            - COALESCE(tc.sum_cancelled_abs, 0),
            ' import_imported=', COALESCE(i.sum_imported, 0)
        )
    FROM (
        SELECT (`ERP_ID` COLLATE utf8mb4_unicode_ci) AS `ERP_ID`
        FROM `Transactions`
        WHERE `type` = 'change'
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
          AND `Status_transaction` IN ('В ожидании', 'Исполнено')
        GROUP BY `ERP_ID`
    ) twe ON twe.`ERP_ID` = b.`ERP_ID`
    LEFT JOIN (
        SELECT
            `ERP_ID`,
            SUM(ABS(COALESCE(`Quantity_change`, 0))) AS sum_replaced_abs
        FROM `Transactions`
        WHERE `type` = 'change'
          AND `Status_transaction` = 'Заменено'
          AND (
               `created_by` IS NULL
            OR `created_by` <> 'deficit_supply'
          )
        GROUP BY `ERP_ID`
    ) tr ON tr.`ERP_ID` = b.`ERP_ID`
    LEFT JOIN (
        SELECT
            `ERP_ID`,
            SUM(COALESCE(`Quantity_change`, 0)) AS sum_deficit_supply
        FROM `Transactions`
        WHERE `type` = 'change'
          AND `Status_transaction` IN ('В ожидании', 'Исполнено', 'Заменено')
          AND `created_by` = 'deficit_supply'
        GROUP BY `ERP_ID`
    ) tds ON tds.`ERP_ID` = b.`ERP_ID`
    LEFT JOIN (
        SELECT
            `ERP_ID`,
            SUM(ABS(COALESCE(`Quantity_change`, 0))) AS sum_cancelled_abs
        FROM `Transactions`
        WHERE `type` = 'change'
          AND `Status_transaction` = 'Отменено'
        GROUP BY `ERP_ID`
    ) tc ON tc.`ERP_ID` = b.`ERP_ID`
    LEFT JOIN (
        SELECT
            `ERP_ID`,
            SUM(COALESCE(`Quantity_change`, 0)) AS sum_imported
        FROM `Import`
        WHERE `Status_import` = 'Импортировано'
        GROUP BY `ERP_ID`
    ) i ON i.`ERP_ID` = b.`ERP_ID`
    WHERE (
            COALESCE(twe.sum_wait_exec, 0)
            - COALESCE(tds.sum_deficit_supply, 0)
            - COALESCE(tc.sum_cancelled_abs, 0)
          ) <> COALESCE(i.sum_imported, 0);
END$$

DELIMITER ;
