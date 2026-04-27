-- import_check: расчет показателей для строк Import со Status_import='Новая'
-- и установка Suggestion по бизнес-правилам.
--
-- Снимок в SET — те же поля, что в Main по ERP_ID; новые реквизиты Transactions
-- (документы, Order_*, Rework_*, Source/Supplier/Location, …) в агрегатах
-- и CASE/SUM не участвуют (используются Quantity_change, Quantity_of_parts_total
-- и перечисленные type / where_from / where_to / Status_*).
-- Тело процедуры совпадает с рабочим вариантом (ниже по BEGIN…END).

DROP PROCEDURE IF EXISTS import_check;

DELIMITER $$

CREATE PROCEDURE import_check()
BEGIN
    /*
      Переменные по ERP_ID:
      - Ожидание поставок: change внешний->склад, В ожидании, Новая
      - Потребность поставок: move склад->(брак|отгрузка|изделие), В ожидании, (Новая|Ожидание поставки)
      - Ожидание закупок: change внешний->склад, В ожидании, В закупке
      - Ожидание изготовления: change внешний->склад, В ожидании, В изготовлении
      - Потребность закупок: move, В ожидании, Ожидание закупки
      - Потребность изготовления: move, В ожидании, Ожидание изготовления

      Производные:
      - Доступность закупок      = ожидание закупок - потребность закупок
      - Доступность изготовления = ожидание изготовления - потребность изготовления
      - Доступность поставок     = ожидание поставок - потребность поставок
      - Доступное ожидаемое поступление = сумма трех доступностей
      - Общее кол-во = Main.Quantity_in_warehouse + доступное ожидаемое поступление
    */

    UPDATE `Import` i
    LEFT JOIN `Main` m
      ON m.`ERP_ID` COLLATE utf8mb4_unicode_ci = i.`ERP_ID` COLLATE utf8mb4_unicode_ci
    LEFT JOIN (
        SELECT
            e.`ERP_ID`,
            e.`expect_supply`,
            COALESCE(ns.`need_supply`, 0) AS `need_supply`,
            e.`expect_purch`,
            e.`expect_prod`,
            COALESCE(np.`need_purch`, 0) AS `need_purch`,
            COALESCE(nm.`need_prod`, 0) AS `need_prod`
        FROM (
            SELECT
                t.`ERP_ID`,
                SUM(
                    CASE
                        WHEN t.`type` = 'change'
                         AND t.`where_from` = 'внешний'
                         AND t.`where_to` = 'склад'
                         AND t.`Status_transaction` = 'В ожидании'
                         AND t.`Status_warehouse` = 'Новая'
                        THEN COALESCE(t.`Quantity_change`, 0)
                        ELSE 0
                    END
                ) AS `expect_supply`,
                SUM(
                    CASE
                        WHEN t.`type` = 'change'
                         AND t.`where_from` = 'внешний'
                         AND t.`where_to` = 'склад'
                         AND t.`Status_transaction` = 'В ожидании'
                         AND t.`Status_warehouse` = 'В закупке'
                        THEN COALESCE(t.`Quantity_change`, 0)
                        ELSE 0
                    END
                ) AS `expect_purch`,
                SUM(
                    CASE
                        WHEN t.`type` = 'change'
                         AND t.`where_from` = 'внешний'
                         AND t.`where_to` = 'склад'
                         AND t.`Status_transaction` = 'В ожидании'
                         AND t.`Status_warehouse` = 'В изготовлении'
                        THEN COALESCE(t.`Quantity_change`, 0)
                        ELSE 0
                    END
                ) AS `expect_prod`
            FROM `Transactions` t
            GROUP BY t.`ERP_ID`
        ) e
        LEFT JOIN (
            SELECT
                t.`ERP_ID`,
                SUM(COALESCE(t.`Quantity_of_parts_total`, 0)) AS `need_supply`
            FROM `Transactions` t
            WHERE t.`type` = 'move'
              AND t.`where_from` = 'склад'
              AND t.`where_to` IN ('брак', 'отгрузка', 'изделие')
              AND t.`Status_transaction` = 'В ожидании'
              AND t.`Status_warehouse` IN ('Новая', 'Ожидание поставки')
            GROUP BY t.`ERP_ID`
        ) ns ON ns.`ERP_ID` COLLATE utf8mb4_unicode_ci = e.`ERP_ID` COLLATE utf8mb4_unicode_ci
        LEFT JOIN (
            SELECT
                t.`ERP_ID`,
                SUM(COALESCE(t.`Quantity_of_parts_total`, 0)) AS `need_purch`
            FROM `Transactions` t
            WHERE t.`type` = 'move'
              AND t.`Status_transaction` = 'В ожидании'
              AND t.`Status_warehouse` = 'Ожидание закупки'
            GROUP BY t.`ERP_ID`
        ) np ON np.`ERP_ID` COLLATE utf8mb4_unicode_ci = e.`ERP_ID` COLLATE utf8mb4_unicode_ci
        LEFT JOIN (
            SELECT
                t.`ERP_ID`,
                SUM(COALESCE(t.`Quantity_of_parts_total`, 0)) AS `need_prod`
            FROM `Transactions` t
            WHERE t.`type` = 'move'
              AND t.`Status_transaction` = 'В ожидании'
              AND t.`Status_warehouse` = 'Ожидание изготовления'
            GROUP BY t.`ERP_ID`
        ) nm ON nm.`ERP_ID` COLLATE utf8mb4_unicode_ci = e.`ERP_ID` COLLATE utf8mb4_unicode_ci
    ) x
      ON x.`ERP_ID` COLLATE utf8mb4_unicode_ci = i.`ERP_ID` COLLATE utf8mb4_unicode_ci
    LEFT JOIN (
        SELECT
            z.`ERP_ID`,
            z.`Target_assembly`,
            z.`Advanced_group`,
            SUM(COALESCE(z.`Quantity_change`, 0)) AS accounted_qty
        FROM `Import` z
        WHERE z.`Status_import` = 'Новая'
          AND z.`type` = 'change'
          AND z.`where_from` = 'внешний'
          AND z.`where_to` = 'склад'
        GROUP BY z.`ERP_ID`, z.`Target_assembly`, z.`Advanced_group`
    ) ic
      ON ic.`ERP_ID` COLLATE utf8mb4_unicode_ci = i.`ERP_ID` COLLATE utf8mb4_unicode_ci
     AND (ic.`Target_assembly` <=> i.`Target_assembly`)
     AND (ic.`Advanced_group` <=> i.`Advanced_group`)
    SET
        i.`Quantity_in_transactions` = COALESCE(x.`expect_supply`, 0),
        i.`inProcess_purchase` = COALESCE(m.`inProcess_purchase`, 0),
        i.`inProcess_manufacturing` = COALESCE(m.`inProcess_manufacturing`, 0),
        i.`Quantity_in_warehouse` = COALESCE(m.`Quantity_in_warehouse`, 0),
        i.`Quantity_in_kitting` = COALESCE(m.`Quantity_in_kitting`, 0),
        i.`Quantity_on_shopfloor` = COALESCE(m.`Quantity_on_shopfloor`, 0),
        i.`Quantity_implemented` = COALESCE(m.`Quantity_implemented`, 0),
        i.`Quantity_shipped` = COALESCE(m.`Quantity_shipped`, 0),
        i.`Quantity_of_losses` = COALESCE(m.`Quantity_of_losses`, 0),
        i.`Quantity_avaliable` =
            (COALESCE(x.`expect_purch`, 0) - COALESCE(x.`need_purch`, 0))
          + (COALESCE(x.`expect_prod`, 0) - COALESCE(x.`need_prod`, 0))
          + (COALESCE(x.`expect_supply`, 0) - COALESCE(x.`need_supply`, 0)),
        i.`Needed_new` = IF(
            (
                COALESCE(i.`Quantity_of_parts_total`, 0)
                - (
                    (COALESCE(x.`expect_purch`, 0) - COALESCE(x.`need_purch`, 0))
                  + (COALESCE(x.`expect_prod`, 0) - COALESCE(x.`need_prod`, 0))
                  + (COALESCE(x.`expect_supply`, 0) - COALESCE(x.`need_supply`, 0))
                )
                - COALESCE(m.`Quantity_in_warehouse`, 0)
            ) > 0,
            (
                COALESCE(i.`Quantity_of_parts_total`, 0)
                - (
                    (COALESCE(x.`expect_purch`, 0) - COALESCE(x.`need_purch`, 0))
                  + (COALESCE(x.`expect_prod`, 0) - COALESCE(x.`need_prod`, 0))
                  + (COALESCE(x.`expect_supply`, 0) - COALESCE(x.`need_supply`, 0))
                )
                - COALESCE(m.`Quantity_in_warehouse`, 0)
            ),
            0
        ),
        i.`Can_be_cancelled_sure` = CASE
            WHEN i.`type` = 'change' AND COALESCE(i.`Quantity_change`, 0) < 0
            THEN COALESCE(x.`expect_supply`, 0)
            ELSE 0
        END,
        i.`Can_be_cancelled_maybe` = CASE
            WHEN i.`type` = 'change' AND COALESCE(i.`Quantity_change`, 0) < 0
            THEN COALESCE(x.`expect_purch`, 0) + COALESCE(x.`expect_prod`, 0)
            ELSE 0
        END,
        i.`Suggestion` = i.`Suggestion`,
        i.`updated_at` = CURRENT_TIMESTAMP
    WHERE i.`Status_import` = 'Новая';

    /* Отдельный пересчет Suggestion по точным условиям ТЗ */
    UPDATE `Import` i
    LEFT JOIN (
        SELECT
            z.`ERP_ID`,
            z.`Target_assembly`,
            z.`Advanced_group`,
            SUM(COALESCE(z.`Quantity_change`, 0)) AS accounted_qty
        FROM `Import` z
        WHERE z.`Status_import` = 'Новая'
          AND z.`type` = 'change'
          AND z.`where_from` = 'внешний'
          AND z.`where_to` = 'склад'
        GROUP BY z.`ERP_ID`, z.`Target_assembly`, z.`Advanced_group`
    ) ic
      ON ic.`ERP_ID` COLLATE utf8mb4_unicode_ci = i.`ERP_ID` COLLATE utf8mb4_unicode_ci
     AND (ic.`Target_assembly` <=> i.`Target_assembly`)
     AND (ic.`Advanced_group` <=> i.`Advanced_group`)
    SET
        i.`Suggestion` = CASE
            WHEN i.`type` = 'move'
             AND i.`where_from` = 'склад'
             AND i.`where_to` IN ('брак', 'отгрузка', 'изделие')
             AND (COALESCE(i.`Needed_new`, 0) - COALESCE(ic.`accounted_qty`, 0)) > 0
            THEN 'Заменить'
            WHEN i.`type` = 'change'
             AND i.`where_from` = 'внешний'
             AND i.`where_to` = 'склад'
             AND COALESCE(i.`Quantity_change`, 0) < 0
             AND (COALESCE(i.`Can_be_cancelled_sure`, 0) + COALESCE(i.`Can_be_cancelled_maybe`, 0)) = 0
            THEN 'Отменить'
            WHEN i.`type` = 'change'
             AND i.`where_from` = 'внешний'
             AND i.`where_to` = 'склад'
             AND COALESCE(i.`Quantity_change`, 0) < 0
             AND ABS(COALESCE(i.`Quantity_change`, 0)) >
                 (COALESCE(i.`Can_be_cancelled_sure`, 0) + COALESCE(i.`Can_be_cancelled_maybe`, 0))
            THEN 'Заменить'
            ELSE 'Импортировать'
        END,
        i.`updated_at` = CURRENT_TIMESTAMP
    WHERE i.`Status_import` = 'Новая';
END$$

DELIMITER ;
