-- Набор процедур bot_* для имитации действий пользователей.
-- Счётчики сценариев в bot_call: FLOOR(5 + RAND() * 11) → целое [5..15].
-- purch_cost в bot_call: FLOOR(5000 + RAND() * 145001) → целое [5000..150000].
-- При UPDATE `Transactions`/`Import`: linked_transaction дополняется (не затирается), как в deficit / move_*.

DELIMITER $$

DROP PROCEDURE IF EXISTS bot_call$$
DROP PROCEDURE IF EXISTS bot_export_user$$
DROP PROCEDURE IF EXISTS bot_purchaser$$
DROP PROCEDURE IF EXISTS bot_purhaser$$
DROP PROCEDURE IF EXISTS bot_shopfloor$$
DROP PROCEDURE IF EXISTS bot_warehouse$$
DROP PROCEDURE IF EXISTS bot_OTK$$

CREATE DEFINER=`bot_ERP`@`%` PROCEDURE bot_export_user(
    IN exp_row_count INT,
    IN exp_approve INT
)
SQL SECURITY DEFINER
BEGIN
    DECLARE v_record_count BIGINT DEFAULT 0;

    /* 1) Случайные "Новая" в Import -> "Выполнить" */
    IF COALESCE(exp_approve, 0) > 0 THEN
        UPDATE `Import` i
        INNER JOIN (
            SELECT z.`id`
            FROM `Import` z
            WHERE z.`Status_import` = 'Новая'
            ORDER BY RAND()
            LIMIT exp_approve
        ) r ON r.`id` = i.`id`
        SET
            i.`Order_import` = 'Выполнить',
            i.`linked_transaction` = CASE
                WHEN i.`linked_transaction` IS NULL OR TRIM(COALESCE(i.`linked_transaction`, '')) = '' THEN CAST(i.id AS CHAR)
                ELSE CONCAT(TRIM(i.`linked_transaction`), '; ', i.id)
            END,
            i.`updated_at`   = CURRENT_TIMESTAMP;
    END IF;

    /* 2) Количество строк в Record_source */
    SELECT COUNT(*) INTO v_record_count
    FROM `Record_source`;

    /* 3) Случайные строки Record_source -> Import */
    IF v_record_count > 0 AND COALESCE(exp_row_count, 0) > 0 THEN
        INSERT INTO `Import` (
            `ERP_ID`, `created_at`, `updated_at`, `created_by`, `updated_by`,
            `linked_transaction`, `type`, `where_from`, `where_to`,
            `Quantity_of_parts_total`, `Quantity_change`,
            `Project`, `Target_assembly`, `Supplied_component_number`, `Component_revision`, `Component_name`,
            `Quantity_in_target_assembly`, `Quantity_of_target_assemblies`,
            `Component_type`, `For_supplied_as_assembly_components_provided_by_supplier`,
            `Components_quantity_in_assembly`, `Part_material`, `Producer`, `Catalogue_number`,
            `Producer_article`, `Distributer`, `Distributer_article`, `MBOM_type`,
            `Mass_kg`, `Unit_of_measure`, `Height`, `Width`, `Length`,
            `Advanced_group`, `Address`, `Document_no`, `Zakaz_no`,
            `Date_needed`, `Date_expected`, `Cost_total_rub`,
            `Supplier`, `Price_of_single_unit`, `Location`, `Source`, `Initial_doc_no`
        )
        SELECT
            r.`ERP_ID`, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, r.`created_by`, r.`updated_by`,
            r.`linked_transaction`, r.`type`, r.`where_from`, r.`where_to`,
            r.`Quantity_of_parts_total`, r.`Quantity_change`,
            r.`Project`, r.`Target_assembly`, r.`Supplied_component_number`, r.`Component_revision`, r.`Component_name`,
            r.`Quantity_in_target_assembly`, r.`Quantity_of_target_assemblies`,
            r.`Component_type`, r.`For_supplied_as_assembly_components_provided_by_supplier`,
            r.`Components_quantity_in_assembly`, r.`Part_material`, r.`Producer`, r.`Catalogue_number`,
            r.`Producer_article`, r.`Distributer`, r.`Distributer_article`, r.`MBOM_type`,
            r.`Mass_kg`, r.`Unit_of_measure`, r.`Height`, r.`Width`, r.`Length`,
            r.`Advanced_group`, r.`Address`, r.`Document_no`, r.`Zakaz_no`,
            r.`Date_needed`, r.`Date_expected`, r.`Cost_total_rub`,
            r.`Supplier`, r.`Price_of_single_unit`, r.`Location`, r.`Source`, r.`Initial_doc_no`
        FROM `Record_source` r
        ORDER BY RAND()
        LIMIT exp_row_count;
    END IF;
END$$

CREATE DEFINER=`bot_ERP`@`%` PROCEDURE bot_purchaser(
    IN purch_purch INT,
    IN purch_manuf INT,
    IN purch_byed INT,
    IN purch_cost BIGINT
)
SQL SECURITY DEFINER
BEGIN
    DROP TEMPORARY TABLE IF EXISTS tmp_bot_purch_picked;
    CREATE TEMPORARY TABLE tmp_bot_purch_picked (
        id INT UNSIGNED PRIMARY KEY
    );

    /* В закупку */
    IF COALESCE(purch_purch, 0) > 0 THEN
        INSERT INTO tmp_bot_purch_picked (id)
        SELECT t.id
        FROM `Transactions` t
        WHERE t.`type` = 'change'
          AND t.`Status_transaction` = 'В ожидании'
          AND t.`Status_warehouse` IN ('Новая', 'Дефицит закупки')
        ORDER BY RAND()
        LIMIT purch_purch;

        UPDATE `Transactions` t
        INNER JOIN tmp_bot_purch_picked p ON p.id = t.id
        SET
            t.`Order_purch` = 'В закупке',
            t.`linked_transaction` = CASE
                WHEN t.`linked_transaction` IS NULL OR TRIM(COALESCE(t.`linked_transaction`, '')) = '' THEN CAST(t.id AS CHAR)
                ELSE CONCAT(TRIM(t.`linked_transaction`), '; ', t.id)
            END,
            t.`updated_by` = CASE
                                WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'bot_purchaser'
                                ELSE CONCAT(t.`updated_by`, '; ', 'bot_purchaser')
                             END,
            t.`updated_at` = CURRENT_TIMESTAMP;
    END IF;

    /* В собственное производство (не из уже выбранных в закупку) */
    IF COALESCE(purch_manuf, 0) > 0 THEN
        UPDATE `Transactions` t
        INNER JOIN (
            SELECT z.id
            FROM `Transactions` z
            LEFT JOIN tmp_bot_purch_picked p ON p.id = z.id
            WHERE z.`type` = 'change'
              AND z.`Status_transaction` = 'В ожидании'
              AND z.`Status_warehouse` IN ('Новая', 'Дефицит закупки')
              AND p.id IS NULL
              AND (z.`Order_purch` IS NULL OR z.`Order_purch` <> 'В закупке')
            ORDER BY RAND()
            LIMIT purch_manuf
        ) r ON r.id = t.id
        SET
            t.`Order_purch` = 'Собственное производство',
            t.`linked_transaction` = CASE
                WHEN t.`linked_transaction` IS NULL OR TRIM(COALESCE(t.`linked_transaction`, '')) = '' THEN CAST(t.id AS CHAR)
                ELSE CONCAT(TRIM(t.`linked_transaction`), '; ', t.id)
            END,
            t.`updated_by` = CASE
                                WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'bot_purchaser'
                                ELSE CONCAT(t.`updated_by`, '; ', 'bot_purchaser')
                             END,
            t.`updated_at` = CURRENT_TIMESTAMP;
    END IF;

    /* Оплачено + стоимость */
    IF COALESCE(purch_byed, 0) > 0 THEN
        UPDATE `Transactions` t
        INNER JOIN (
            SELECT z.id
            FROM `Transactions` z
            WHERE z.`type` = 'change'
              AND z.`Status_transaction` = 'В ожидании'
              AND z.`Status_warehouse` = 'В закупке'
            ORDER BY RAND()
            LIMIT purch_byed
        ) r ON r.id = t.id
        SET
            t.`Order_purch` = 'Оплачено',
            t.`Cost_total_rub` = purch_cost,
            t.`linked_transaction` = CASE
                WHEN t.`linked_transaction` IS NULL OR TRIM(COALESCE(t.`linked_transaction`, '')) = '' THEN CAST(t.id AS CHAR)
                ELSE CONCAT(TRIM(t.`linked_transaction`), '; ', t.id)
            END,
            t.`updated_by` = CASE
                                WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'bot_purchaser'
                                ELSE CONCAT(t.`updated_by`, '; ', 'bot_purchaser')
                             END,
            t.`updated_at` = CURRENT_TIMESTAMP;
    END IF;

    DROP TEMPORARY TABLE IF EXISTS tmp_bot_purch_picked;
END$$

/* Совместимость с именем из задания (с опечаткой). */
CREATE DEFINER=`bot_ERP`@`%` PROCEDURE bot_purhaser(
    IN purch_purch INT,
    IN purch_manuf INT,
    IN purch_byed INT,
    IN purch_cost BIGINT
)
SQL SECURITY DEFINER
BEGIN
    CALL bot_purchaser(purch_purch, purch_manuf, purch_byed, purch_cost);
END$$

CREATE DEFINER=`bot_ERP`@`%` PROCEDURE bot_shopfloor(
    IN prod_purch INT,
    IN prod_prod INT,
    IN prod_manuf INT,
    IN prod_kit INT,
    IN prod_assembled INT,
    IN prod_shipped INT,
    IN prod_loss INT
)
SQL SECURITY DEFINER
BEGIN
    /* change: закупка -> Order_prod='В закупку' */
    IF COALESCE(prod_purch, 0) > 0 THEN
        UPDATE `Transactions` t
        INNER JOIN (
            SELECT z.id
            FROM `Transactions` z
            WHERE z.`type` = 'change'
              AND z.`Status_transaction` = 'В ожидании'
              AND z.`Status_warehouse` IN ('Новая', 'Норма', 'Дефицит закупки')
              AND z.`Order_purch` = 'В закупке'
            ORDER BY RAND()
            LIMIT prod_purch
        ) r ON r.id = t.id
        SET t.`Order_prod` = 'В закупку',
            t.`linked_transaction` = CASE
                WHEN t.`linked_transaction` IS NULL OR TRIM(COALESCE(t.`linked_transaction`, '')) = '' THEN CAST(t.id AS CHAR)
                ELSE CONCAT(TRIM(t.`linked_transaction`), '; ', t.id)
            END,
            t.`updated_by` = CASE WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'bot_shopfloor' ELSE CONCAT(t.`updated_by`, '; ', 'bot_shopfloor') END,
            t.`updated_at` = CURRENT_TIMESTAMP;
    END IF;

    /* change: собственное производство -> Принято в изготовление */
    IF COALESCE(prod_prod, 0) > 0 THEN
        UPDATE `Transactions` t
        INNER JOIN (
            SELECT z.id
            FROM `Transactions` z
            WHERE z.`type` = 'change'
              AND z.`Status_transaction` = 'В ожидании'
              AND z.`Status_warehouse` IN ('Новая', 'Норма', 'Дефицит закупки')
              AND z.`Order_purch` = 'Собственное производство'
            ORDER BY RAND()
            LIMIT prod_prod
        ) r ON r.id = t.id
        SET t.`Order_prod` = 'Принято в изготовление',
            t.`linked_transaction` = CASE
                WHEN t.`linked_transaction` IS NULL OR TRIM(COALESCE(t.`linked_transaction`, '')) = '' THEN CAST(t.id AS CHAR)
                ELSE CONCAT(TRIM(t.`linked_transaction`), '; ', t.id)
            END,
            t.`updated_by` = CASE WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'bot_shopfloor' ELSE CONCAT(t.`updated_by`, '; ', 'bot_shopfloor') END,
            t.`updated_at` = CURRENT_TIMESTAMP;
    END IF;

    /* change: В изготовлении -> Изготовлено */
    IF COALESCE(prod_manuf, 0) > 0 THEN
        UPDATE `Transactions` t
        INNER JOIN (
            SELECT z.id
            FROM `Transactions` z
            WHERE z.`type` = 'change'
              AND z.`Status_transaction` = 'В ожидании'
              AND z.`Status_warehouse` = 'В изготовлении'
            ORDER BY RAND()
            LIMIT prod_manuf
        ) r ON r.id = t.id
        SET t.`Order_prod` = 'Изготовлено',
            t.`linked_transaction` = CASE
                WHEN t.`linked_transaction` IS NULL OR TRIM(COALESCE(t.`linked_transaction`, '')) = '' THEN CAST(t.id AS CHAR)
                ELSE CONCAT(TRIM(t.`linked_transaction`), '; ', t.id)
            END,
            t.`updated_by` = CASE WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'bot_shopfloor' ELSE CONCAT(t.`updated_by`, '; ', 'bot_shopfloor') END,
            t.`updated_at` = CURRENT_TIMESTAMP;
    END IF;

    /* move: Комплектация -> Принято со склада (см. move_kit_to_shopfloor) */
    IF COALESCE(prod_kit, 0) > 0 THEN
        UPDATE `Transactions` t
        INNER JOIN (
            SELECT z.id
            FROM `Transactions` z
            WHERE z.`type` = 'move'
              AND z.`Status_transaction` = 'В ожидании'
              AND z.`Status_warehouse` = 'Комплектация'
            ORDER BY RAND()
            LIMIT prod_kit
        ) r ON r.id = t.id
        SET t.`Order_prod` = 'Принято со склада',
            t.`linked_transaction` = CASE
                WHEN t.`linked_transaction` IS NULL OR TRIM(COALESCE(t.`linked_transaction`, '')) = '' THEN CAST(t.id AS CHAR)
                ELSE CONCAT(TRIM(t.`linked_transaction`), '; ', t.id)
            END,
            t.`updated_by` = CASE WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'bot_shopfloor' ELSE CONCAT(t.`updated_by`, '; ', 'bot_shopfloor') END,
            t.`updated_at` = CURRENT_TIMESTAMP;
    END IF;

    /* move: Сборка -> Изготовлено */
    IF COALESCE(prod_assembled, 0) > 0 THEN
        UPDATE `Transactions` t
        INNER JOIN (
            SELECT z.id
            FROM `Transactions` z
            WHERE z.`type` = 'move'
              AND z.`Status_transaction` = 'В ожидании'
              AND z.`Status_warehouse` = 'Сборка'
            ORDER BY RAND()
            LIMIT prod_assembled
        ) r ON r.id = t.id
        SET t.`Order_prod` = 'Изготовлено',
            t.`linked_transaction` = CASE
                WHEN t.`linked_transaction` IS NULL OR TRIM(COALESCE(t.`linked_transaction`, '')) = '' THEN CAST(t.id AS CHAR)
                ELSE CONCAT(TRIM(t.`linked_transaction`), '; ', t.id)
            END,
            t.`updated_by` = CASE WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'bot_shopfloor' ELSE CONCAT(t.`updated_by`, '; ', 'bot_shopfloor') END,
            t.`updated_at` = CURRENT_TIMESTAMP;
    END IF;

    /* move: Упаковка -> Отгружено */
    IF COALESCE(prod_shipped, 0) > 0 THEN
        UPDATE `Transactions` t
        INNER JOIN (
            SELECT z.id
            FROM `Transactions` z
            WHERE z.`type` = 'move'
              AND z.`Status_transaction` = 'В ожидании'
              AND z.`Status_warehouse` = 'Упаковка'
            ORDER BY RAND()
            LIMIT prod_shipped
        ) r ON r.id = t.id
        SET t.`Order_prod` = 'Отгружено',
            t.`linked_transaction` = CASE
                WHEN t.`linked_transaction` IS NULL OR TRIM(COALESCE(t.`linked_transaction`, '')) = '' THEN CAST(t.id AS CHAR)
                ELSE CONCAT(TRIM(t.`linked_transaction`), '; ', t.id)
            END,
            t.`updated_by` = CASE WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'bot_shopfloor' ELSE CONCAT(t.`updated_by`, '; ', 'bot_shopfloor') END,
            t.`updated_at` = CURRENT_TIMESTAMP;
    END IF;

    /* move: Утилизация -> Забраковать */
    IF COALESCE(prod_loss, 0) > 0 THEN
        UPDATE `Transactions` t
        INNER JOIN (
            SELECT z.id
            FROM `Transactions` z
            WHERE z.`type` = 'move'
              AND z.`Status_transaction` = 'В ожидании'
              AND z.`Status_warehouse` = 'Утилизация'
            ORDER BY RAND()
            LIMIT prod_loss
        ) r ON r.id = t.id
        SET t.`Order_prod` = 'Забраковать',
            t.`linked_transaction` = CASE
                WHEN t.`linked_transaction` IS NULL OR TRIM(COALESCE(t.`linked_transaction`, '')) = '' THEN CAST(t.id AS CHAR)
                ELSE CONCAT(TRIM(t.`linked_transaction`), '; ', t.id)
            END,
            t.`updated_by` = CASE WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'bot_shopfloor' ELSE CONCAT(t.`updated_by`, '; ', 'bot_shopfloor') END,
            t.`updated_at` = CURRENT_TIMESTAMP;
    END IF;
END$$

CREATE DEFINER=`bot_ERP`@`%` PROCEDURE bot_warehouse(
    IN wh_purch INT,
    IN wh_manuf INT,
    IN wh_return INT,
    IN wh_kit INT
)
SQL SECURITY DEFINER
BEGIN
    IF COALESCE(wh_purch, 0) > 0 THEN
        UPDATE `Transactions` t
        INNER JOIN (
            SELECT z.id
            FROM `Transactions` z
            WHERE z.`type` = 'change'
              AND z.`Status_transaction` = 'В ожидании'
              AND z.`Status_warehouse` = 'В закупке'
              AND z.`Order_purch` = 'Оплачено'
              AND z.`Cost_total_rub` IS NOT NULL
            ORDER BY RAND()
            LIMIT wh_purch
        ) r ON r.id = t.id
        SET t.`Order_prod` = 'В закупку',
            t.`linked_transaction` = CASE
                WHEN t.`linked_transaction` IS NULL OR TRIM(COALESCE(t.`linked_transaction`, '')) = '' THEN CAST(t.id AS CHAR)
                ELSE CONCAT(TRIM(t.`linked_transaction`), '; ', t.id)
            END,
            t.`updated_by` = CASE WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'bot_warehouse' ELSE CONCAT(t.`updated_by`, '; ', 'bot_warehouse') END,
            t.`updated_at` = CURRENT_TIMESTAMP;
    END IF;

    IF COALESCE(wh_manuf, 0) > 0 THEN
        UPDATE `Transactions` t
        INNER JOIN (
            SELECT z.id
            FROM `Transactions` z
            WHERE z.`type` = 'change'
              AND z.`Status_transaction` = 'В ожидании'
              AND z.`Status_warehouse` = 'В изготовлении'
              AND z.`Order_prod` = 'Изготовлено'
              AND z.`Order_OTK` = 'Принято'
            ORDER BY RAND()
            LIMIT wh_manuf
        ) r ON r.id = t.id
        SET t.`Order_wh` = 'Принято на склад',
            t.`linked_transaction` = CASE
                WHEN t.`linked_transaction` IS NULL OR TRIM(COALESCE(t.`linked_transaction`, '')) = '' THEN CAST(t.id AS CHAR)
                ELSE CONCAT(TRIM(t.`linked_transaction`), '; ', t.id)
            END,
            t.`updated_by` = CASE WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'bot_warehouse' ELSE CONCAT(t.`updated_by`, '; ', 'bot_warehouse') END,
            t.`updated_at` = CURRENT_TIMESTAMP;
    END IF;

    IF COALESCE(wh_return, 0) > 0 THEN
        UPDATE `Transactions` t
        INNER JOIN (
            SELECT z.id
            FROM `Transactions` z
            WHERE z.`type` = 'move'
              AND z.`Status_transaction` = 'В ожидании'
              AND z.`Order_prod` = 'Вернуть на склад'
            ORDER BY RAND()
            LIMIT wh_return
        ) r ON r.id = t.id
        SET t.`Order_wh` = 'Принято на склад',
            t.`linked_transaction` = CASE
                WHEN t.`linked_transaction` IS NULL OR TRIM(COALESCE(t.`linked_transaction`, '')) = '' THEN CAST(t.id AS CHAR)
                ELSE CONCAT(TRIM(t.`linked_transaction`), '; ', t.id)
            END,
            t.`updated_by` = CASE WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'bot_warehouse' ELSE CONCAT(t.`updated_by`, '; ', 'bot_warehouse') END,
            t.`updated_at` = CURRENT_TIMESTAMP;
    END IF;

    IF COALESCE(wh_kit, 0) > 0 THEN
        UPDATE `Transactions` t
        INNER JOIN (
            SELECT z.id
            FROM `Transactions` z
            WHERE z.`Status_transaction` = 'В ожидании'
              AND z.`Status_warehouse` = 'Комплектация'
            ORDER BY RAND()
            LIMIT wh_kit
        ) r ON r.id = t.id
        SET t.`Order_wh` = 'Списано со склада',
            t.`linked_transaction` = CASE
                WHEN t.`linked_transaction` IS NULL OR TRIM(COALESCE(t.`linked_transaction`, '')) = '' THEN CAST(t.id AS CHAR)
                ELSE CONCAT(TRIM(t.`linked_transaction`), '; ', t.id)
            END,
            t.`updated_by` = CASE WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'bot_warehouse' ELSE CONCAT(t.`updated_by`, '; ', 'bot_warehouse') END,
            t.`updated_at` = CURRENT_TIMESTAMP;
    END IF;
END$$

CREATE DEFINER=`bot_ERP`@`%` PROCEDURE bot_OTK(
    IN OTK_manuf INT,
    IN OTK_assembly INT,
    IN OTK_shipped INT,
    IN OTK_loss INT
)
SQL SECURITY DEFINER
BEGIN
    IF COALESCE(OTK_manuf, 0) > 0 THEN
        UPDATE `Transactions` t
        INNER JOIN (
            SELECT z.id
            FROM `Transactions` z
            WHERE z.`Status_transaction` = 'В ожидании'
              AND z.`Status_warehouse` = 'В изготовлении'
              AND z.`Order_prod` = 'Изготовлено'
            ORDER BY RAND()
            LIMIT OTK_manuf
        ) r ON r.id = t.id
        SET t.`Order_OTK` = 'Принято',
            t.`linked_transaction` = CASE
                WHEN t.`linked_transaction` IS NULL OR TRIM(COALESCE(t.`linked_transaction`, '')) = '' THEN CAST(t.id AS CHAR)
                ELSE CONCAT(TRIM(t.`linked_transaction`), '; ', t.id)
            END,
            t.`updated_by` = CASE WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'bot_OTK' ELSE CONCAT(t.`updated_by`, '; ', 'bot_OTK') END,
            t.`updated_at` = CURRENT_TIMESTAMP;
    END IF;

    IF COALESCE(OTK_assembly, 0) > 0 THEN
        UPDATE `Transactions` t
        INNER JOIN (
            SELECT z.id
            FROM `Transactions` z
            WHERE z.`Status_transaction` = 'В ожидании'
              AND z.`Status_warehouse` = 'Сборка'
              AND z.`Order_prod` = 'Изготовлено'
            ORDER BY RAND()
            LIMIT OTK_assembly
        ) r ON r.id = t.id
        SET t.`Order_OTK` = 'Принято',
            t.`linked_transaction` = CASE
                WHEN t.`linked_transaction` IS NULL OR TRIM(COALESCE(t.`linked_transaction`, '')) = '' THEN CAST(t.id AS CHAR)
                ELSE CONCAT(TRIM(t.`linked_transaction`), '; ', t.id)
            END,
            t.`updated_by` = CASE WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'bot_OTK' ELSE CONCAT(t.`updated_by`, '; ', 'bot_OTK') END,
            t.`updated_at` = CURRENT_TIMESTAMP;
    END IF;

    IF COALESCE(OTK_shipped, 0) > 0 THEN
        UPDATE `Transactions` t
        INNER JOIN (
            SELECT z.id
            FROM `Transactions` z
            WHERE z.`Status_transaction` = 'В ожидании'
              AND z.`Status_warehouse` = 'Упаковка'
              AND z.`Order_prod` = 'Отгружено'
            ORDER BY RAND()
            LIMIT OTK_shipped
        ) r ON r.id = t.id
        SET t.`Order_OTK` = 'Принято',
            t.`linked_transaction` = CASE
                WHEN t.`linked_transaction` IS NULL OR TRIM(COALESCE(t.`linked_transaction`, '')) = '' THEN CAST(t.id AS CHAR)
                ELSE CONCAT(TRIM(t.`linked_transaction`), '; ', t.id)
            END,
            t.`updated_by` = CASE WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'bot_OTK' ELSE CONCAT(t.`updated_by`, '; ', 'bot_OTK') END,
            t.`updated_at` = CURRENT_TIMESTAMP;
    END IF;

    IF COALESCE(OTK_loss, 0) > 0 THEN
        UPDATE `Transactions` t
        INNER JOIN (
            SELECT z.id
            FROM `Transactions` z
            WHERE z.`Status_transaction` = 'В ожидании'
              AND z.`Status_warehouse` = 'Утилизация'
              AND z.`Order_prod` = 'Забраковать'
            ORDER BY RAND()
            LIMIT OTK_loss
        ) r ON r.id = t.id
        SET t.`Order_OTK` = 'Забраковано',
            t.`linked_transaction` = CASE
                WHEN t.`linked_transaction` IS NULL OR TRIM(COALESCE(t.`linked_transaction`, '')) = '' THEN CAST(t.id AS CHAR)
                ELSE CONCAT(TRIM(t.`linked_transaction`), '; ', t.id)
            END,
            t.`updated_by` = CASE WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'bot_OTK' ELSE CONCAT(t.`updated_by`, '; ', 'bot_OTK') END,
            t.`updated_at` = CURRENT_TIMESTAMP;
    END IF;
END$$

CREATE DEFINER=`bot_ERP`@`%` PROCEDURE bot_call()
SQL SECURITY DEFINER
BEGIN
    /* Один проход: Export → Purchaser → Shopfloor → Warehouse → OTK. */

    DECLARE exp_row_count INT;   /* limit строк Record_source → Import */
    DECLARE exp_approve INT;     /* limit строк Import: Новая → Выполнить */

    DECLARE purch_purch INT;
    DECLARE purch_manuf INT;
    DECLARE purch_byed INT;      /* куплено; имя параметра bot_purchaser, как в API */
    DECLARE purch_cost BIGINT;   /* подставляется в Cost_total_rub при «Оплачено» */

    DECLARE prod_purch INT;
    DECLARE prod_prod INT;
    DECLARE prod_manuf INT;
    DECLARE prod_kit INT;
    DECLARE prod_assembled INT;
    DECLARE prod_shipped INT;
    DECLARE prod_loss INT;

    DECLARE wh_purch INT;
    DECLARE wh_manuf INT;
    DECLARE wh_return INT;
    DECLARE wh_kit INT;

    DECLARE OTK_manuf INT;
    DECLARE OTK_assembly INT;
    DECLARE OTK_shipped INT;
    DECLARE OTK_loss INT;

    /* Случайные лимиты сценариев: [5..15]; cost — [5000..150000]. */
    SET exp_row_count  = FLOOR(5 + RAND() * 11);
    SET exp_approve    = FLOOR(5 + RAND() * 11);

    SET purch_purch    = FLOOR(5 + RAND() * 11);
    SET purch_manuf    = FLOOR(5 + RAND() * 11);
    SET purch_byed     = FLOOR(5 + RAND() * 11);
    SET purch_cost     = FLOOR(5000 + RAND() * 145001);

    SET prod_purch     = FLOOR(5 + RAND() * 11);
    SET prod_prod      = FLOOR(5 + RAND() * 11);
    SET prod_manuf     = FLOOR(5 + RAND() * 11);
    SET prod_kit       = FLOOR(5 + RAND() * 11);
    SET prod_assembled = FLOOR(5 + RAND() * 11);
    SET prod_shipped   = FLOOR(5 + RAND() * 11);
    SET prod_loss      = FLOOR(5 + RAND() * 11);

    SET wh_purch       = FLOOR(5 + RAND() * 11);
    SET wh_manuf       = FLOOR(5 + RAND() * 11);
    SET wh_return      = FLOOR(5 + RAND() * 11);
    SET wh_kit         = FLOOR(5 + RAND() * 11);

    SET OTK_manuf      = FLOOR(5 + RAND() * 11);
    SET OTK_assembly   = FLOOR(5 + RAND() * 11);
    SET OTK_shipped    = FLOOR(5 + RAND() * 11);
    SET OTK_loss       = FLOOR(5 + RAND() * 11);

    CALL bot_export_user(exp_row_count, exp_approve);
    CALL bot_purchaser(purch_purch, purch_manuf, purch_byed, purch_cost);
    CALL bot_shopfloor(prod_purch, prod_prod, prod_manuf, prod_kit, prod_assembled, prod_shipped, prod_loss);
    CALL bot_warehouse(wh_purch, wh_manuf, wh_return, wh_kit);
    CALL bot_OTK(OTK_manuf, OTK_assembly, OTK_shipped, OTK_loss);
END$$

DELIMITER ;
