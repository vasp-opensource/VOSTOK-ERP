-- check_data_integrity: проверки согласованности Main и Transactions; нарушения пишутся в integrity_check_log.
-- Отборы по «открытым» / «закрытым» согласованы с процедурами move_wh_to_shopfloor, move_kit_to_shopfloor,
-- ch_outside_to_purch, ch_outside_to_ownProd, move_shop_to_fin. При смене бизнес-правил скорректируйте WHERE.
-- Производство (2b): после ch_outside_to_ownProd открытый change — where_to=«собственное производство», Status_warehouse=«В изготовлении»;
--   до обработки — where_to=«закупка» + Order_purch/Order_prod и Status_warehouse IN («Новая», «Дефицит закупки»).
-- Закупка (2c): по каждому ERP_ID сумма количества по move (Status_warehouse=«Ожидание закупки») <= суммы Quantity_change по change (Status_warehouse=«В закупке»).
--
-- Дополнительно: отсутствие Main для ERP_ID не считается ошибкой, пока все релевантные транзакции
--   только в «В ожидании» (ещё не направлены в закупку/изготовление — строка Main не создаётся).
--
-- Антидубль логирования:
--   если такой же текст ошибки уже есть в integrity_check_log за последние 3 дня,
--   повторно в лог не пишем.

DROP PROCEDURE IF EXISTS check_data_integrity;

DELIMITER $$

CREATE PROCEDURE check_data_integrity()
BEGIN
    DROP TEMPORARY TABLE IF EXISTS tmp_integrity_candidates;
    CREATE TEMPORARY TABLE tmp_integrity_candidates (
        error_message TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL
    );

    /* 1) Комплектация: сумма открытых move со статусом склада «Комплектация» = Main.Quantity_in_kitting */
    INSERT INTO `tmp_integrity_candidates` (`error_message`)
    SELECT
        CONCAT(
            'Комплектация: ERP_ID=', COALESCE(t.ERP_ID, m.ERP_ID),
            ' sum_open=', COALESCE(t.tx_sum, 0),
            ' Main.Quantity_in_kitting=', COALESCE(m.Quantity_in_kitting, 0)
        )
    FROM `Main` m
    LEFT JOIN (
        SELECT
            `ERP_ID`,
            SUM(
                IF(
                    COALESCE(`Quantity_of_parts_total`, 0) > 0,
                    `Quantity_of_parts_total`,
                    COALESCE(`Quantity_change`, 0)
                )
            ) AS tx_sum
        FROM `Transactions`
        WHERE `type` = 'move'
          AND (`Status_transaction` IS NULL OR `Status_transaction` = 'В ожидании')
          AND `Status_warehouse` = 'Комплектация'
        GROUP BY `ERP_ID`
    ) t ON t.`ERP_ID` = m.`ERP_ID`
    WHERE COALESCE(t.tx_sum, 0) <> COALESCE(m.`Quantity_in_kitting`, 0);

    INSERT INTO `tmp_integrity_candidates` (`error_message`)
    SELECT
        CONCAT(
            'Комплектация: ERP_ID=', t.`ERP_ID`,
            ' sum_open=', t.tx_sum,
            ' Main: строки нет (ожидалось 0 в комплектации)'
        )
    FROM (
        SELECT
            `ERP_ID`,
            SUM(
                IF(
                    COALESCE(`Quantity_of_parts_total`, 0) > 0,
                    `Quantity_of_parts_total`,
                    COALESCE(`Quantity_change`, 0)
                )
            ) AS tx_sum
        FROM `Transactions`
        WHERE `type` = 'move'
          AND (`Status_transaction` IS NULL OR `Status_transaction` = 'В ожидании')
          AND `Status_warehouse` = 'Комплектация'
        GROUP BY `ERP_ID`
    ) t
    LEFT JOIN `Main` m ON m.`ERP_ID` = t.`ERP_ID`
    WHERE m.`ERP_ID` IS NULL
      AND t.tx_sum <> 0;

    /* 2a) Закупка: открытые change «в закупку» = Main.inProcess_purchase */
    INSERT INTO `tmp_integrity_candidates` (`error_message`)
    SELECT
        CONCAT(
            'Закупка (открытые change): ERP_ID=', COALESCE(t.ERP_ID, m.ERP_ID),
            ' sum_open=', COALESCE(t.tx_sum, 0),
            ' Main.inProcess_purchase=', COALESCE(m.`inProcess_purchase`, 0)
        )
    FROM `Main` m
    LEFT JOIN (
        SELECT
            `ERP_ID`,
            SUM(COALESCE(`Quantity_change`, 0)) AS tx_sum
        FROM `Transactions`
        WHERE `type` = 'change'
          AND `where_from` = 'внешний'
          AND `where_to` = 'закупка'
          AND `Order_prod` = 'В закупку'
          AND `Order_purch` IN ('В закупке', 'Оплачено')
          AND (`Status_transaction` IS NULL OR `Status_transaction` = 'В ожидании')
        GROUP BY `ERP_ID`
    ) t ON t.`ERP_ID` = m.`ERP_ID`
    WHERE COALESCE(t.tx_sum, 0) <> COALESCE(m.`inProcess_purchase`, 0);

    INSERT INTO `tmp_integrity_candidates` (`error_message`)
    SELECT
        CONCAT(
            'Закупка (открытые change): ERP_ID=', t.`ERP_ID`,
            ' sum_open=', t.tx_sum,
            ' Main: строки нет'
        )
    FROM (
        SELECT
            `ERP_ID`,
            SUM(COALESCE(`Quantity_change`, 0)) AS tx_sum
        FROM `Transactions`
        WHERE `type` = 'change'
          AND `where_from` = 'внешний'
          AND `where_to` = 'закупка'
          AND `Order_prod` = 'В закупку'
          AND `Order_purch` IN ('В закупке', 'Оплачено')
          AND (`Status_transaction` IS NULL OR `Status_transaction` = 'В ожидании')
        GROUP BY `ERP_ID`
    ) t
    LEFT JOIN `Main` m ON m.`ERP_ID` = t.`ERP_ID`
    WHERE m.`ERP_ID` IS NULL
      AND t.tx_sum <> 0;

    /* 2b) Производство: открытые change по собственному изготовлению = Main.inProcess_manufacturing
       После ch_outside_to_ownProd строки получают where_to = «собственное производство», Status_warehouse = «В изготовлении»;
       до обработки — «закупка» + Order_purch/Order_prod (см. tmp_ownprod_change_ids). Учитываем оба состояния. */
    INSERT INTO `tmp_integrity_candidates` (`error_message`)
    SELECT
        CONCAT(
            'Производство (открытые change): ERP_ID=', COALESCE(t.ERP_ID, m.ERP_ID),
            ' sum_open=', COALESCE(t.tx_sum, 0),
            ' Main.inProcess_manufacturing=', COALESCE(m.`inProcess_manufacturing`, 0)
        )
    FROM `Main` m
    LEFT JOIN (
        SELECT
            `ERP_ID`,
            SUM(COALESCE(`Quantity_change`, 0)) AS tx_sum
        FROM `Transactions`
        WHERE `type` = 'change'
          AND `where_from` = 'внешний'
          AND (
              (
                  `where_to` = 'собственное производство'
                  AND `Status_warehouse` = 'В изготовлении'
              )
              OR (
                  `where_to` = 'закупка'
                  AND `Order_purch` = 'Собственное производство'
                  AND `Order_prod` = 'Принято в изготовление'
                  AND `Status_warehouse` IN ('Новая', 'Дефицит закупки')
              )
          )
          AND (`Status_transaction` IS NULL OR `Status_transaction` = 'В ожидании')
        GROUP BY `ERP_ID`
    ) t ON t.`ERP_ID` = m.`ERP_ID`
    WHERE COALESCE(t.tx_sum, 0) <> COALESCE(m.`inProcess_manufacturing`, 0);

    INSERT INTO `tmp_integrity_candidates` (`error_message`)
    SELECT
        CONCAT(
            'Производство (открытые change): ERP_ID=', t.`ERP_ID`,
            ' sum_open=', t.tx_sum,
            ' Main: строки нет'
        )
    FROM (
        SELECT
            `ERP_ID`,
            SUM(COALESCE(`Quantity_change`, 0)) AS tx_sum
        FROM `Transactions`
        WHERE `type` = 'change'
          AND `where_from` = 'внешний'
          AND (
              (
                  `where_to` = 'собственное производство'
                  AND `Status_warehouse` = 'В изготовлении'
              )
              OR (
                  `where_to` = 'закупка'
                  AND `Order_purch` = 'Собственное производство'
                  AND `Order_prod` = 'Принято в изготовление'
                  AND `Status_warehouse` IN ('Новая', 'Дефицит закупки')
              )
          )
          AND (`Status_transaction` IS NULL OR `Status_transaction` = 'В ожидании')
        GROUP BY `ERP_ID`
    ) t
    LEFT JOIN `Main` m ON m.`ERP_ID` = t.`ERP_ID`
    WHERE m.`ERP_ID` IS NULL
      AND t.tx_sum <> 0;

    /* 2c) Закупка: по ERP_ID сумма кол-ва move «Ожидание закупки» <= суммы Quantity_change по change «В закупке»
       (как в прочих move — потребность: Quantity_of_parts_total, иначе Quantity_change). */
    INSERT INTO `tmp_integrity_candidates` (`error_message`)
    SELECT
        CONCAT(
            'Закупка (move «Ожидание закупки» vs change «В закупке»): ERP_ID=', mv.`ERP_ID`,
            ' qty_move=', mv.qty_move,
            ' qty_change=', COALESCE(ch.qty_change, 0)
        )
    FROM (
        SELECT
            `ERP_ID`,
            SUM(
                IF(
                    COALESCE(`Quantity_of_parts_total`, 0) > 0,
                    `Quantity_of_parts_total`,
                    COALESCE(`Quantity_change`, 0)
                )
            ) AS qty_move
        FROM `Transactions`
        WHERE `type` = 'move'
          AND `Status_warehouse` = 'Ожидание закупки'
        GROUP BY `ERP_ID`
    ) mv
    LEFT JOIN (
        SELECT
            `ERP_ID`,
            SUM(COALESCE(`Quantity_change`, 0)) AS qty_change
        FROM `Transactions`
        WHERE `type` = 'change'
          AND `Status_warehouse` = 'В закупке'
        GROUP BY `ERP_ID`
    ) ch ON ch.`ERP_ID` = mv.`ERP_ID`
    WHERE mv.qty_move > COALESCE(ch.qty_change, 0);

    /* 3) По каждому ERP_ID: сумма закрытых change (Исполнено) = сумма количественных полей Main
          без inProcess_purchase / inProcess_manufacturing (там — незакрытые change). */
    INSERT INTO `tmp_integrity_candidates` (`error_message`)
    SELECT
        CONCAT(
            'Закрытые change vs сумма Quantity_* в Main: ERP_ID=', COALESCE(t.`ERP_ID`, m.`ERP_ID`),
            ' sum_closed_change=', COALESCE(t.tx_sum, 0),
            ' sum_main=',
            COALESCE(m.`Quantity_in_warehouse`, 0)
                + COALESCE(m.`Quantity_in_kitting`, 0)
                + COALESCE(m.`Quantity_on_shopfloor`, 0)
                + COALESCE(m.`Quantity_implemented`, 0)
                + COALESCE(m.`Quantity_shipped`, 0)
                + COALESCE(m.`Quantity_of_losses`, 0)
        )
    FROM `Main` m
    LEFT JOIN (
        SELECT
            `ERP_ID`,
            SUM(COALESCE(`Quantity_change`, 0)) AS tx_sum
        FROM `Transactions`
        WHERE `type` = 'change'
          AND `Status_transaction` = 'Исполнено'
        GROUP BY `ERP_ID`
    ) t ON t.`ERP_ID` = m.`ERP_ID`
    WHERE COALESCE(t.tx_sum, 0) <> COALESCE(m.`Quantity_in_warehouse`, 0)
        + COALESCE(m.`Quantity_in_kitting`, 0)
        + COALESCE(m.`Quantity_on_shopfloor`, 0)
        + COALESCE(m.`Quantity_implemented`, 0)
        + COALESCE(m.`Quantity_shipped`, 0)
        + COALESCE(m.`Quantity_of_losses`, 0);

    INSERT INTO `tmp_integrity_candidates` (`error_message`)
    SELECT
        CONCAT(
            'Закрытые change vs сумма Quantity_* в Main: ERP_ID=', t.`ERP_ID`,
            ' sum_closed_change=', t.tx_sum,
            ' Main: строки нет'
        )
    FROM (
        SELECT
            `ERP_ID`,
            SUM(COALESCE(`Quantity_change`, 0)) AS tx_sum
        FROM `Transactions`
        WHERE `type` = 'change'
          AND `Status_transaction` = 'Исполнено'
        GROUP BY `ERP_ID`
    ) t
    LEFT JOIN `Main` m ON m.`ERP_ID` = t.`ERP_ID`
    WHERE m.`ERP_ID` IS NULL
      AND t.tx_sum <> 0;

    /* 7) По ERP_ID:
          sum(change, Status_transaction IN ('В ожидании','Исполнено'))
          - sum(abs(change), Status_transaction='Заменено')
          = sum(Import.Quantity_change, Status_import='Импортировано') */
    INSERT INTO `tmp_integrity_candidates` (`error_message`)
    SELECT
        CONCAT(
            'Transactions vs Import (change): ERP_ID=', b.`ERP_ID`,
            ' tx_wait_exec=', COALESCE(twe.sum_wait_exec, 0),
            ' tx_replaced_abs=', COALESCE(tr.sum_replaced_abs, 0),
            ' tx_result=', COALESCE(twe.sum_wait_exec, 0) - COALESCE(tr.sum_replaced_abs, 0),
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
        GROUP BY `ERP_ID`
    ) tr ON tr.`ERP_ID` = b.`ERP_ID`
    LEFT JOIN (
        SELECT
            `ERP_ID`,
            SUM(COALESCE(`Quantity_change`, 0)) AS sum_imported
        FROM `Import`
        WHERE `Status_import` = 'Импортировано'
        GROUP BY `ERP_ID`
    ) i ON i.`ERP_ID` = b.`ERP_ID`
    WHERE (COALESCE(twe.sum_wait_exec, 0) - COALESCE(tr.sum_replaced_abs, 0))
          <> COALESCE(i.sum_imported, 0);

    /* 4-6) Закрытые move в брак / отгрузку / изделие = Quantity_of_losses / Quantity_shipped / Quantity_implemented */
    INSERT INTO `tmp_integrity_candidates` (`error_message`)
    SELECT
        CONCAT(
            'Брак (закрытые move where_to=брак): ERP_ID=', COALESCE(t.ERP_ID, m.ERP_ID),
            ' sum_closed=', COALESCE(t.tx_sum, 0),
            ' Main.Quantity_of_losses=', COALESCE(m.`Quantity_of_losses`, 0)
        )
    FROM `Main` m
    LEFT JOIN (
        SELECT
            `ERP_ID`,
            SUM(
                IF(
                    COALESCE(`Quantity_of_parts_total`, 0) > 0,
                    `Quantity_of_parts_total`,
                    COALESCE(`Quantity_change`, 0)
                )
            ) AS tx_sum
        FROM `Transactions`
        WHERE `type` = 'move'
          AND `where_to` = 'брак'
          AND `Status_transaction` = 'Исполнено'
        GROUP BY `ERP_ID`
    ) t ON t.`ERP_ID` = m.`ERP_ID`
    WHERE COALESCE(t.tx_sum, 0) <> COALESCE(m.`Quantity_of_losses`, 0);

    INSERT INTO `tmp_integrity_candidates` (`error_message`)
    SELECT
        CONCAT(
            'Брак (закрытые move): ERP_ID=', t.`ERP_ID`,
            ' sum_closed=', t.tx_sum,
            ' Main: строки нет'
        )
    FROM (
        SELECT
            `ERP_ID`,
            SUM(
                IF(
                    COALESCE(`Quantity_of_parts_total`, 0) > 0,
                    `Quantity_of_parts_total`,
                    COALESCE(`Quantity_change`, 0)
                )
            ) AS tx_sum
        FROM `Transactions`
        WHERE `type` = 'move'
          AND `where_to` = 'брак'
          AND `Status_transaction` = 'Исполнено'
        GROUP BY `ERP_ID`
    ) t
    LEFT JOIN `Main` m ON m.`ERP_ID` = t.`ERP_ID`
    WHERE m.`ERP_ID` IS NULL
      AND t.tx_sum <> 0;

    INSERT INTO `tmp_integrity_candidates` (`error_message`)
    SELECT
        CONCAT(
            'Отгрузка (закрытые move where_to=отгрузка): ERP_ID=', COALESCE(t.ERP_ID, m.ERP_ID),
            ' sum_closed=', COALESCE(t.tx_sum, 0),
            ' Main.Quantity_shipped=', COALESCE(m.`Quantity_shipped`, 0)
        )
    FROM `Main` m
    LEFT JOIN (
        SELECT
            `ERP_ID`,
            SUM(
                IF(
                    COALESCE(`Quantity_of_parts_total`, 0) > 0,
                    `Quantity_of_parts_total`,
                    COALESCE(`Quantity_change`, 0)
                )
            ) AS tx_sum
        FROM `Transactions`
        WHERE `type` = 'move'
          AND `where_to` = 'отгрузка'
          AND `Status_transaction` = 'Исполнено'
        GROUP BY `ERP_ID`
    ) t ON t.`ERP_ID` = m.`ERP_ID`
    WHERE COALESCE(t.tx_sum, 0) <> COALESCE(m.`Quantity_shipped`, 0);

    INSERT INTO `tmp_integrity_candidates` (`error_message`)
    SELECT
        CONCAT(
            'Отгрузка (закрытые move): ERP_ID=', t.`ERP_ID`,
            ' sum_closed=', t.tx_sum,
            ' Main: строки нет'
        )
    FROM (
        SELECT
            `ERP_ID`,
            SUM(
                IF(
                    COALESCE(`Quantity_of_parts_total`, 0) > 0,
                    `Quantity_of_parts_total`,
                    COALESCE(`Quantity_change`, 0)
                )
            ) AS tx_sum
        FROM `Transactions`
        WHERE `type` = 'move'
          AND `where_to` = 'отгрузка'
          AND `Status_transaction` = 'Исполнено'
        GROUP BY `ERP_ID`
    ) t
    LEFT JOIN `Main` m ON m.`ERP_ID` = t.`ERP_ID`
    WHERE m.`ERP_ID` IS NULL
      AND t.tx_sum <> 0;

    INSERT INTO `tmp_integrity_candidates` (`error_message`)
    SELECT
        CONCAT(
            'Изделие (закрытые move where_to=изделие): ERP_ID=', COALESCE(t.ERP_ID, m.ERP_ID),
            ' sum_closed=', COALESCE(t.tx_sum, 0),
            ' Main.Quantity_implemented=', COALESCE(m.`Quantity_implemented`, 0)
        )
    FROM `Main` m
    LEFT JOIN (
        SELECT
            `ERP_ID`,
            SUM(
                IF(
                    COALESCE(`Quantity_of_parts_total`, 0) > 0,
                    `Quantity_of_parts_total`,
                    COALESCE(`Quantity_change`, 0)
                )
            ) AS tx_sum
        FROM `Transactions`
        WHERE `type` = 'move'
          AND `where_to` = 'изделие'
          AND `Status_transaction` = 'Исполнено'
        GROUP BY `ERP_ID`
    ) t ON t.`ERP_ID` = m.`ERP_ID`
    WHERE COALESCE(t.tx_sum, 0) <> COALESCE(m.`Quantity_implemented`, 0);

    INSERT INTO `tmp_integrity_candidates` (`error_message`)
    SELECT
        CONCAT(
            'Изделие (закрытые move): ERP_ID=', t.`ERP_ID`,
            ' sum_closed=', t.tx_sum,
            ' Main: строки нет'
        )
    FROM (
        SELECT
            `ERP_ID`,
            SUM(
                IF(
                    COALESCE(`Quantity_of_parts_total`, 0) > 0,
                    `Quantity_of_parts_total`,
                    COALESCE(`Quantity_change`, 0)
                )
            ) AS tx_sum
        FROM `Transactions`
        WHERE `type` = 'move'
          AND `where_to` = 'изделие'
          AND `Status_transaction` = 'Исполнено'
        GROUP BY `ERP_ID`
    ) t
    LEFT JOIN `Main` m ON m.`ERP_ID` = t.`ERP_ID`
    WHERE m.`ERP_ID` IS NULL
      AND t.tx_sum <> 0;

    /* Дополнительно: ERP_ID с движениями, но без строки в Main — только если уже есть шаги
       после «В ожидании» (иначе Main ещё не создаётся до ch_outside_* / закупка / изготовление). */
    INSERT INTO `tmp_integrity_candidates` (`error_message`)
    SELECT
        CONCAT(
            'Нет строки Main для ERP_ID=', d.`ERP_ID`,
            ' (есть транзакции с ненулевым количеством и статусом транзакции не только «В ожидании»)'
        )
    FROM (
        SELECT DISTINCT `ERP_ID`
        FROM `Transactions`
        WHERE COALESCE(`Quantity_of_parts_total`, 0) <> 0
           OR COALESCE(`Quantity_change`, 0) <> 0
    ) d
    LEFT JOIN `Main` m ON m.`ERP_ID` = d.`ERP_ID`
    WHERE m.`ERP_ID` IS NULL
      AND EXISTS (
          SELECT 1
          FROM `Transactions` t
          WHERE t.`ERP_ID` = d.`ERP_ID`
            AND (
                COALESCE(t.`Quantity_of_parts_total`, 0) <> 0
                OR COALESCE(t.`Quantity_change`, 0) <> 0
            )
            AND NOT (t.`Status_transaction` IS NULL OR t.`Status_transaction` = 'В ожидании')
      );

    /* Запись в лог без дублей за последние 3 дня */
    INSERT INTO `integrity_check_log` (`created_at`, `procedure_name`, `error_message`)
    SELECT
        NOW(),
        'check_data_integrity',
        c.`error_message`
    FROM (
        SELECT DISTINCT `error_message`
        FROM `tmp_integrity_candidates`
    ) c
    WHERE NOT EXISTS (
        SELECT 1
        FROM `integrity_check_log` l
        WHERE l.`procedure_name` = 'check_data_integrity'
          AND l.`error_message` = (c.`error_message` COLLATE utf8mb4_unicode_ci)
          AND l.`created_at` >= NOW() - INTERVAL 3 DAY
    );

    DROP TEMPORARY TABLE IF EXISTS tmp_integrity_candidates;
END$$

DELIMITER ;
