-- check_data_integrity: проверки согласованности Main и Transactions; нарушения пишутся в integrity_check_log.
-- После блока (3) вызывается check_imported_quantity (сверка импорта с Main).
-- Отборы по «открытым» / «закрытым» согласованы с процедурами move_wh_to_shopfloor, move_kit_to_shopfloor,
-- ch_outside_to_purch, ch_outside_to_ownProd, move_shop_to_fin. При смене бизнес-правил скорректируйте WHERE.
-- Внешние change: type=change, where_from=«внешний», where_to=«склад». Контур закупка/производство — только по Source и Status_warehouse
-- (поля Order_purch, Order_wh, Order_prod, Order_OTK пользователи могут менять вручную — в проверках не используются).
-- Закупка (2a): SUM(Quantity_change) по открытым change, В закупке, Покупное (или NULL/пустой Source как закупка) = Main.inProcess_purchase.
-- Производство (2b): SUM(Quantity_change) по открытым change, В изготовлении, Собственное производство = Main.inProcess_manufacturing.
-- Закупка (2c): move «Ожидание закупки» с тем же контуром Source (закупка) ≤ change «В закупке» с тем же контуром.
-- 2d–2e: несовместимость Status_warehouse и Source на открытых change (без Order_*).
--
-- Дополнительно: отсутствие Main для ERP_ID не считается ошибкой, пока все релевантные транзакции
--   только в «В ожидании», со складом «Дефицит закупки», либо уже «Заменено»/«Отменено» (архив после unite/deficit и т.п.).
--
-- Дополнительные идеи проверок (при необходимости включить отдельно):
--   • linked_transaction указывает на несуществующий id;
--   • отрицательные Quantity_* в Main;
--   • дублирующиеся «активные» move на один ERP_ID с одинаковым маршрутом;
--   • расхождение SUM по закупке/производству, если в БД появятся новые Order_prod / Order_purch.

DELIMITER $$

DROP PROCEDURE IF EXISTS check_data_integrity$$

CREATE PROCEDURE check_data_integrity()
BEGIN
    DROP TEMPORARY TABLE IF EXISTS tmp_integrity_candidates;
    CREATE TEMPORARY TABLE tmp_integrity_candidates (
        `procedure_name` VARCHAR(255) NOT NULL,
        `ERP_ID` VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
        `error_message` TEXT NOT NULL
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

    /* 1) Комплектация: сумма открытых move со статусом склада «Комплектация» = Main.Quantity_in_kitting */
    INSERT INTO `tmp_integrity_candidates` (`procedure_name`, `ERP_ID`, `error_message`)
    SELECT
        'check_data_integrity',
        COALESCE(t.`ERP_ID`, m.`ERP_ID`),
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

    INSERT INTO `tmp_integrity_candidates` (`procedure_name`, `ERP_ID`, `error_message`)
    SELECT
        'check_data_integrity',
        t.`ERP_ID`,
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

    /* 2a) Закупка: открытые change (внешний→склад, В ожидании, В закупке, контур Покупное) = Main.inProcess_purchase */
    INSERT INTO `tmp_integrity_candidates` (`procedure_name`, `ERP_ID`, `error_message`)
    SELECT
        'check_data_integrity',
        COALESCE(t.`ERP_ID`, m.`ERP_ID`),
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
          AND `where_to` = 'склад'
          AND (`Status_transaction` IS NULL OR `Status_transaction` = 'В ожидании')
          AND `Status_warehouse` = 'В закупке'
          AND (
               `Source` = 'Покупное'
            OR `Source` IS NULL
            OR TRIM(COALESCE(`Source`, '')) = ''
          )
        GROUP BY `ERP_ID`
    ) t ON t.`ERP_ID` = m.`ERP_ID`
    WHERE COALESCE(t.tx_sum, 0) <> COALESCE(m.`inProcess_purchase`, 0);

    INSERT INTO `tmp_integrity_candidates` (`procedure_name`, `ERP_ID`, `error_message`)
    SELECT
        'check_data_integrity',
        t.`ERP_ID`,
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
          AND `where_to` = 'склад'
          AND (`Status_transaction` IS NULL OR `Status_transaction` = 'В ожидании')
          AND `Status_warehouse` = 'В закупке'
          AND (
               `Source` = 'Покупное'
            OR `Source` IS NULL
            OR TRIM(COALESCE(`Source`, '')) = ''
          )
        GROUP BY `ERP_ID`
    ) t
    LEFT JOIN `Main` m ON m.`ERP_ID` = t.`ERP_ID`
    WHERE m.`ERP_ID` IS NULL
      AND t.tx_sum <> 0;

    /* 2b) Производство: открытые change (внешний→склад, В ожидании, В изготовлении, Собственное производство) = Main.inProcess_manufacturing */
    INSERT INTO `tmp_integrity_candidates` (`procedure_name`, `ERP_ID`, `error_message`)
    SELECT
        'check_data_integrity',
        COALESCE(t.`ERP_ID`, m.`ERP_ID`),
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
          AND `where_to` = 'склад'
          AND (`Status_transaction` IS NULL OR `Status_transaction` = 'В ожидании')
          AND `Status_warehouse` = 'В изготовлении'
          AND `Source` = 'Собственное производство'
        GROUP BY `ERP_ID`
    ) t ON t.`ERP_ID` = m.`ERP_ID`
    WHERE COALESCE(t.tx_sum, 0) <> COALESCE(m.`inProcess_manufacturing`, 0);

    INSERT INTO `tmp_integrity_candidates` (`procedure_name`, `ERP_ID`, `error_message`)
    SELECT
        'check_data_integrity',
        t.`ERP_ID`,
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
          AND `where_to` = 'склад'
          AND (`Status_transaction` IS NULL OR `Status_transaction` = 'В ожидании')
          AND `Status_warehouse` = 'В изготовлении'
          AND `Source` = 'Собственное производство'
        GROUP BY `ERP_ID`
    ) t
    LEFT JOIN `Main` m ON m.`ERP_ID` = t.`ERP_ID`
    WHERE m.`ERP_ID` IS NULL
      AND t.tx_sum <> 0;

    /* 2d) Контур закупки на складе: Source не должен быть «Собственное производство». */
    INSERT INTO `tmp_integrity_candidates` (`procedure_name`, `ERP_ID`, `error_message`)
    SELECT
        'check_data_integrity',
        `ERP_ID`,
        CONCAT(
            'Source (закупка): ERP_ID=', `ERP_ID`,
            ' id=', `id`,
            ' Source=Собственное производство при Status_warehouse=В закупке'
        )
    FROM `Transactions`
    WHERE `type` = 'change'
      AND `where_from` = 'внешний'
      AND `where_to` = 'склад'
      AND (`Status_transaction` IS NULL OR `Status_transaction` = 'В ожидании')
      AND `Status_warehouse` = 'В закупке'
      AND `Source` = 'Собственное производство';

    /* 2e) Контур изготовления на складе: Source не должен быть «Покупное». */
    INSERT INTO `tmp_integrity_candidates` (`procedure_name`, `ERP_ID`, `error_message`)
    SELECT
        'check_data_integrity',
        `ERP_ID`,
        CONCAT(
            'Source (производство): ERP_ID=', `ERP_ID`,
            ' id=', `id`,
            ' Source=Покупное при Status_warehouse=В изготовлении'
        )
    FROM `Transactions`
    WHERE `type` = 'change'
      AND `where_from` = 'внешний'
      AND `where_to` = 'склад'
      AND (`Status_transaction` IS NULL OR `Status_transaction` = 'В ожидании')
      AND `Status_warehouse` = 'В изготовлении'
      AND `Source` = 'Покупное';

    /* 2c) Закупка: move «Ожидание закупки» (контур Покупное) ≤ change «В закупке» (тот же контур по Source). */
    INSERT INTO `tmp_integrity_candidates` (`procedure_name`, `ERP_ID`, `error_message`)
    SELECT
        'check_data_integrity',
        mv.`ERP_ID`,
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
          AND (
               `Source` = 'Покупное'
            OR `Source` IS NULL
            OR TRIM(COALESCE(`Source`, '')) = ''
          )
        GROUP BY `ERP_ID`
    ) mv
    LEFT JOIN (
        SELECT
            `ERP_ID`,
            SUM(COALESCE(`Quantity_change`, 0)) AS qty_change
        FROM `Transactions`
        WHERE `type` = 'change'
          AND `where_from` = 'внешний'
          AND `where_to` = 'склад'
          AND `Status_warehouse` = 'В закупке'
          AND (
               `Source` = 'Покупное'
            OR `Source` IS NULL
            OR TRIM(COALESCE(`Source`, '')) = ''
          )
        GROUP BY `ERP_ID`
    ) ch ON ch.`ERP_ID` = mv.`ERP_ID`
    WHERE mv.qty_move > COALESCE(ch.qty_change, 0);

    /* 3) По каждому ERP_ID: сумма закрытых change (Исполнено) = сумма количественных полей Main
          без inProcess_purchase / inProcess_manufacturing (там — незакрытые change).
          В sum_main входит в т.ч. Quantity_of_rework. */
    INSERT INTO `tmp_integrity_candidates` (`procedure_name`, `ERP_ID`, `error_message`)
    SELECT
        'check_data_integrity',
        COALESCE(t.`ERP_ID`, m.`ERP_ID`),
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
                + COALESCE(m.`Quantity_of_rework`, 0)
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
        + COALESCE(m.`Quantity_of_losses`, 0)
        + COALESCE(m.`Quantity_of_rework`, 0);

    INSERT INTO `tmp_integrity_candidates` (`procedure_name`, `ERP_ID`, `error_message`)
    SELECT
        'check_data_integrity',
        t.`ERP_ID`,
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

    CALL check_imported_quantity();

    /* 4–6) Закрытые move в брак / отгрузку / изделие = Quantity_of_losses / Quantity_shipped / Quantity_implemented */
    INSERT INTO `tmp_integrity_candidates` (`procedure_name`, `ERP_ID`, `error_message`)
    SELECT
        'check_data_integrity',
        COALESCE(t.`ERP_ID`, m.`ERP_ID`),
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

    INSERT INTO `tmp_integrity_candidates` (`procedure_name`, `ERP_ID`, `error_message`)
    SELECT
        'check_data_integrity',
        t.`ERP_ID`,
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

    INSERT INTO `tmp_integrity_candidates` (`procedure_name`, `ERP_ID`, `error_message`)
    SELECT
        'check_data_integrity',
        COALESCE(t.`ERP_ID`, m.`ERP_ID`),
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

    INSERT INTO `tmp_integrity_candidates` (`procedure_name`, `ERP_ID`, `error_message`)
    SELECT
        'check_data_integrity',
        t.`ERP_ID`,
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

    INSERT INTO `tmp_integrity_candidates` (`procedure_name`, `ERP_ID`, `error_message`)
    SELECT
        'check_data_integrity',
        COALESCE(t.`ERP_ID`, m.`ERP_ID`),
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

    INSERT INTO `tmp_integrity_candidates` (`procedure_name`, `ERP_ID`, `error_message`)
    SELECT
        'check_data_integrity',
        t.`ERP_ID`,
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

    /* Дополнительно: ERP_ID с движениями, но без строки в Main — только если уже есть «активная»
       строка не в состоянии ожидания по процессу (иначе Main ещё не создаётся).
       Не считаются ложным признаком: склад «Дефицит закупки» / «Ожидание поставки»;
       транзакция «Заменено»/«Отменено» (старые строки после unite / split). */
    INSERT INTO `tmp_integrity_candidates` (`procedure_name`, `ERP_ID`, `error_message`)
    SELECT
        'check_data_integrity',
        d.`ERP_ID`,
        CONCAT(
            'Нет строки Main для ERP_ID=', d.`ERP_ID`,
            ' (есть транзакции с ненулевым количеством и статусом транзакции не только «В ожидании»',
            ', не «Заменено»/«Отменено», не в статусах склада «Дефицит закупки»/«Ожидание поставки»)'
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
            AND NOT (
                t.`Status_transaction` IS NULL
                OR t.`Status_transaction` = 'В ожидании'
                OR t.`Status_transaction` IN ('Заменено', 'Отменено')
                OR TRIM(COALESCE(t.`Status_warehouse`, '')) = 'Дефицит закупки'
                OR TRIM(COALESCE(t.`Status_warehouse`, '')) = 'Ожидание поставки'
            )
      );

    /* Пишем только новые ошибки: если такой же текст по тому же ERP_ID уже был, повторно не логируем. */
    INSERT INTO `integrity_check_log` (`procedure_name`, `ERP_ID`, `error_message`)
    SELECT DISTINCT
        c.`procedure_name`,
        c.`ERP_ID`,
        c.`error_message`
    FROM `tmp_integrity_candidates` c
    WHERE NOT EXISTS (
        SELECT 1
        FROM `integrity_check_log` l
        WHERE l.`procedure_name` = c.`procedure_name`
          AND (l.`ERP_ID` <=> c.`ERP_ID`)
          AND l.`error_message` = (c.`error_message` COLLATE utf8mb4_unicode_ci)
    );

    DROP TEMPORARY TABLE IF EXISTS tmp_integrity_candidates;
END$$

DELIMITER ;
