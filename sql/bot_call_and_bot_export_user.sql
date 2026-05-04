-- Набор процедур bot_* для имитации действий пользователей.
-- bot_call генерирует случайные лимиты сценариев и вызывает export/purchase/shopfloor/warehouse/OTK/supervisor.
-- export: exp_row_count = [5..15], exp_approve = [10..20].
-- purch_cost в bot_call: FLOOR(5000 + RAND() * 145001) → целое [5000..150000].

DELIMITER $$

DROP PROCEDURE IF EXISTS bot_call$$
DROP PROCEDURE IF EXISTS bot_export_user$$
DROP PROCEDURE IF EXISTS bot_purchaser$$
DROP PROCEDURE IF EXISTS bot_purhaser$$
DROP PROCEDURE IF EXISTS bot_purcaser$$
DROP PROCEDURE IF EXISTS bot_shopfloor$$
DROP PROCEDURE IF EXISTS bot_warehouse$$
DROP PROCEDURE IF EXISTS bot_OTK$$
DROP PROCEDURE IF EXISTS bot_supervisor$$

CREATE DEFINER=`export`@`%` PROCEDURE bot_export_user(
    IN exp_row_count INT,
    IN exp_approve INT
)
SQL SECURITY DEFINER
BEGIN
    DECLARE v_record_count BIGINT DEFAULT 0;
    DECLARE v_projects TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

    SELECT NULLIF(TRIM(MAX(CASE WHEN `variable_name` = 'Projects' THEN `text_parameter` END)), '')
      INTO v_projects
    FROM `bot_parameters`;

    /* 1) Подтвердить случайные новые строки импорта с готовой рекомендацией. */
    IF COALESCE(exp_approve, 0) > 0 THEN
        UPDATE `Import` i
        INNER JOIN (
            SELECT picked.`id`
            FROM (
                SELECT z.`id`
                FROM `Import` z
                WHERE z.`Status_import` = 'Новая'
                  AND z.`Suggestion` IN ('Импортировать', 'Отменить', 'Заменить')
                  AND (z.`Order_import` IS NULL OR z.`Order_import` <> 'Выполнить')
              AND (
                    v_projects IS NULL
                 OR TRIM(COALESCE(v_projects, '')) = ''
                 OR FIND_IN_SET(
                      TRIM(COALESCE(CAST(z.`Project` AS CHAR CHARACTER SET utf8mb4), '')) COLLATE utf8mb4_unicode_ci,
                      REPLACE(v_projects, ', ', ',') COLLATE utf8mb4_unicode_ci
                    ) > 0
              )
                ORDER BY RAND()
                LIMIT exp_approve
            ) picked
        ) r ON r.`id` = i.`id`
        SET
            i.`Order_import` = 'Выполнить',
            i.`updated_by` = CASE
                WHEN i.`updated_by` IS NULL OR TRIM(COALESCE(i.`updated_by`, '')) = '' THEN 'export'
                ELSE CONCAT(i.`updated_by`, '; ', 'export')
            END,
            i.`updated_at`   = CURRENT_TIMESTAMP;
    END IF;

    /* 2) Количество строк в Record_source */
    SELECT COUNT(*) INTO v_record_count
    FROM `Record_source`;

    /* 3) Случайные строки из всего Record_source -> Import */
    IF v_record_count > 0 AND COALESCE(exp_row_count, 0) > 0 THEN
        INSERT INTO `Import` (
            `ERP_ID`, `created_at`, `updated_at`, `created_by`, `updated_by`,
            `linked_transaction`, `type`, `where_from`, `where_to`,
            `Quantity_of_parts_total`, `Quantity_change`,
            `Project`, `Target_assembly`, `Supplied_component_number`, `Component_revision`, `Component_name`,
            `Quantity_in_target_assembly`, `Quantity_of_target_assemblies`,
            `Component_type`, `For_supplied_as_assembly_components_provided_by_supplier`,
            `Components_quantity_in_assembly`,
            `Assembly_batch_id`, `Assembly_batch_name`, `Assembly_batch_status`, `Assembly_batch_priority`,
            `Part_material`, `Producer`, `Catalogue_number`,
            `Producer_article`, `Distributer`, `Distributer_article`, `MBOM_type`,
            `Mass_kg`, `Unit_of_measure`, `Height`, `Width`, `Length`,
            `Advanced_group`, `Address`, `Document_no`, `Zakaz_no`,
            `Date_needed`, `Date_expected`, `Cost_total_rub`,
            `Supplier`, `Price_of_single_unit`, `Location`, `Source`, `Initial_doc_no`
        )
        SELECT
            r.`ERP_ID`, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 'export', 'export',
            r.`linked_transaction`, r.`type`, r.`where_from`, r.`where_to`,
            r.`Quantity_of_parts_total`, r.`Quantity_change`,
            r.`Project`, r.`Target_assembly`, r.`Supplied_component_number`, r.`Component_revision`, r.`Component_name`,
            r.`Quantity_in_target_assembly`, r.`Quantity_of_target_assemblies`,
            r.`Component_type`, r.`For_supplied_as_assembly_components_provided_by_supplier`,
            r.`Components_quantity_in_assembly`,
            NULL, NULL, NULL, NULL,
            r.`Part_material`, r.`Producer`, r.`Catalogue_number`,
            r.`Producer_article`, r.`Distributer`, r.`Distributer_article`, r.`MBOM_type`,
            r.`Mass_kg`, r.`Unit_of_measure`, r.`Height`, r.`Width`, r.`Length`,
            r.`Advanced_group`, r.`Address`, r.`Document_no`, r.`Zakaz_no`,
            r.`Date_needed`, r.`Date_expected`, r.`Cost_total_rub`,
            r.`Supplier`, r.`Price_of_single_unit`, r.`Location`, r.`Source`, r.`Initial_doc_no`
        FROM `Record_source` r
        WHERE (
              v_projects IS NULL
           OR TRIM(COALESCE(v_projects, '')) = ''
           OR FIND_IN_SET(
                TRIM(COALESCE(CAST(r.`Project` AS CHAR CHARACTER SET utf8mb4), '')) COLLATE utf8mb4_unicode_ci,
                REPLACE(v_projects, ', ', ',') COLLATE utf8mb4_unicode_ci
              ) > 0
        )
        ORDER BY RAND()
        LIMIT exp_row_count;
    END IF;
END$$

GRANT EXECUTE ON PROCEDURE `VOSTOK_ERP`.`bot_export_user` TO 'export'@'%'$$
GRANT EXECUTE ON PROCEDURE `VOSTOK_ERP`.`bot_export_user` TO 'bot_ERP'@'%'$$
GRANT SELECT ON `VOSTOK_ERP`.`bot_parameters` TO 'export'@'%'$$
GRANT SELECT ON `VOSTOK_ERP`.`bot_parameters` TO 'bot_ERP'@'%'$$

CREATE DEFINER=`bot_ERP`@`%` PROCEDURE bot_purchaser(
    IN purch_purch INT,
    IN purch_byed INT,
    IN purch_manuf INT,
    IN prod_rework INT,
    IN purch_return INT,
    IN purch_cost BIGINT
)
SQL SECURITY DEFINER
BEGIN
    DECLARE v_projects TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

    SELECT NULLIF(TRIM(MAX(CASE WHEN `variable_name` = 'Projects' THEN `text_parameter` END)), '')
      INTO v_projects
    FROM `bot_parameters`;

    /* Рекомендация в производство, но закупщик отправляет в закупку. */
    IF COALESCE(purch_manuf, 0) > 0 THEN
        UPDATE `Transactions` t
        INNER JOIN (
            SELECT id FROM (
                SELECT z.id
                FROM `Transactions` z
                WHERE z.`type` = 'change'
                  AND z.`Status_transaction` = 'В ожидании'
                  AND z.`Status_warehouse` = 'Новая'
                  AND (
                      z.`Recommend_purchprod` IS NULL
                      OR (z.`Recommend_purchprod` = 'В собственное производство' AND z.`Order_prod` = 'В закупку')
                  )
              AND (
                    v_projects IS NULL
                 OR TRIM(COALESCE(v_projects, '')) = ''
                 OR FIND_IN_SET(
                      TRIM(COALESCE(CAST(z.`Project` AS CHAR CHARACTER SET utf8mb4), '')) COLLATE utf8mb4_unicode_ci,
                      REPLACE(v_projects, ', ', ',') COLLATE utf8mb4_unicode_ci
                    ) > 0
              )
                ORDER BY RAND()
                LIMIT purch_manuf
            ) picked
        ) r ON r.id = t.id
        SET
            t.`Order_purch` = 'В закупке',
            t.`updated_by` = CASE
                                WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'purchase'
                                ELSE CONCAT(t.`updated_by`, '; ', 'purchase')
                             END,
            t.`updated_at` = CURRENT_TIMESTAMP;
    END IF;

    /* Рекомендация в закупку -> закупщик подтверждает закупку. */
    IF COALESCE(purch_purch, 0) > 0 THEN
        UPDATE `Transactions` t
        INNER JOIN (
            SELECT id FROM (
                SELECT z.id
                FROM `Transactions` z
                WHERE z.`type` = 'change'
                  AND z.`Status_transaction` = 'В ожидании'
                  AND z.`Status_warehouse` = 'Новая'
                  AND z.`Recommend_purchprod` = 'В закупку'
                  AND (z.`Order_purch` IS NULL OR z.`Order_purch` <> 'В закупке')
              AND (
                    v_projects IS NULL
                 OR TRIM(COALESCE(v_projects, '')) = ''
                 OR FIND_IN_SET(
                      TRIM(COALESCE(CAST(z.`Project` AS CHAR CHARACTER SET utf8mb4), '')) COLLATE utf8mb4_unicode_ci,
                      REPLACE(v_projects, ', ', ',') COLLATE utf8mb4_unicode_ci
                    ) > 0
              )
                ORDER BY RAND()
                LIMIT purch_purch
            ) picked
        ) r ON r.id = t.id
        SET
            t.`Order_purch` = 'В закупке',
            t.`updated_by` = CASE
                                WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'purchase'
                                ELSE CONCAT(t.`updated_by`, '; ', 'purchase')
                             END,
            t.`updated_at` = CURRENT_TIMESTAMP;
    END IF;

    /* Закупщик может перекинуть рекомендованную закупку в собственное производство. */
    IF COALESCE(purch_manuf, 0) > 0 THEN
        UPDATE `Transactions` t
        INNER JOIN (
            SELECT id FROM (
                SELECT z.id
                FROM `Transactions` z
                WHERE z.`type` = 'change'
                  AND z.`Status_transaction` = 'В ожидании'
                  AND z.`Status_warehouse` = 'Новая'
                  AND z.`Recommend_purchprod` = 'В закупку'
                  AND (z.`Order_purch` IS NULL OR z.`Order_purch` NOT IN ('В закупке', 'В собственное производство'))
              AND (
                    v_projects IS NULL
                 OR TRIM(COALESCE(v_projects, '')) = ''
                 OR FIND_IN_SET(
                      TRIM(COALESCE(CAST(z.`Project` AS CHAR CHARACTER SET utf8mb4), '')) COLLATE utf8mb4_unicode_ci,
                      REPLACE(v_projects, ', ', ',') COLLATE utf8mb4_unicode_ci
                    ) > 0
              )
                ORDER BY RAND()
                LIMIT purch_manuf
            ) picked
        ) r ON r.id = t.id
        SET
            t.`Order_purch` = 'В собственное производство',
            t.`updated_by` = CASE
                                WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'purchase'
                                ELSE CONCAT(t.`updated_by`, '; ', 'purchase')
                             END,
            t.`updated_at` = CURRENT_TIMESTAMP;
    END IF;

    /* Уточнения по закупке -> закупщик подтверждает закупку. */
    IF COALESCE(purch_purch, 0) > 0 THEN
        UPDATE `Transactions` t
        INNER JOIN (
            SELECT z.id
            FROM `Transactions` z
            WHERE z.`type` = 'change'
              AND z.`Status_transaction` = 'В ожидании'
              AND z.`Status_warehouse` = 'Новая'
              AND z.`Recommend_purchprod` = 'Уточнить кол-во в закупке'
              AND (
                    v_projects IS NULL
                 OR TRIM(COALESCE(v_projects, '')) = ''
                 OR FIND_IN_SET(
                      TRIM(COALESCE(CAST(z.`Project` AS CHAR CHARACTER SET utf8mb4), '')) COLLATE utf8mb4_unicode_ci,
                      REPLACE(v_projects, ', ', ',') COLLATE utf8mb4_unicode_ci
                    ) > 0
              )
            ORDER BY RAND()
            LIMIT purch_purch
        ) r ON r.id = t.id
        SET
            t.`Order_purch` = 'В закупке',
            t.`updated_by` = CASE
                                WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'purchase'
                                ELSE CONCAT(t.`updated_by`, '; ', 'purchase')
                             END,
            t.`updated_at` = CURRENT_TIMESTAMP;

        UPDATE `Transactions` t
        INNER JOIN (
            SELECT z.id
            FROM `Transactions` z
            WHERE z.`type` = 'change'
              AND z.`Status_transaction` = 'В ожидании'
              AND z.`Status_warehouse` = 'Новая'
              AND z.`Recommend_purchprod` = 'Уточнить ревизию в закупке'
              AND (
                    v_projects IS NULL
                 OR TRIM(COALESCE(v_projects, '')) = ''
                 OR FIND_IN_SET(
                      TRIM(COALESCE(CAST(z.`Project` AS CHAR CHARACTER SET utf8mb4), '')) COLLATE utf8mb4_unicode_ci,
                      REPLACE(v_projects, ', ', ',') COLLATE utf8mb4_unicode_ci
                    ) > 0
              )
            ORDER BY RAND()
            LIMIT purch_purch
        ) r ON r.id = t.id
        SET
            t.`Order_purch` = 'В закупке',
            t.`updated_by` = CASE
                                WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'purchase'
                                ELSE CONCAT(t.`updated_by`, '; ', 'purchase')
                             END,
            t.`updated_at` = CURRENT_TIMESTAMP;
    END IF;

    /* Оплачено + стоимость + случайный документ */
    IF COALESCE(purch_byed, 0) > 0 THEN
        UPDATE `Transactions` t
        INNER JOIN (
            SELECT
                picked.id,
                doc.`id` AS Document_id,
                doc.`Document_no`,
                doc.`Document_date`
            FROM (
                SELECT z.id
                FROM `Transactions` z
                WHERE z.`type` = 'change'
                  AND z.`Status_transaction` = 'В ожидании'
                  AND z.`Status_warehouse` = 'В закупке'
              AND (
                    v_projects IS NULL
                 OR TRIM(COALESCE(v_projects, '')) = ''
                 OR FIND_IN_SET(
                      TRIM(COALESCE(CAST(z.`Project` AS CHAR CHARACTER SET utf8mb4), '')) COLLATE utf8mb4_unicode_ci,
                      REPLACE(v_projects, ', ', ',') COLLATE utf8mb4_unicode_ci
                    ) > 0
              )
                ORDER BY RAND()
                LIMIT purch_byed
            ) picked
            INNER JOIN `Documents` doc ON doc.`id` = (
                SELECT d.`id`
                FROM `Documents` d
                ORDER BY RAND()
                LIMIT 1
            )
        ) r ON r.id = t.id
        SET
            t.`Order_purch` = 'Оплачено',
            t.`Cost_total_rub` = purch_cost,
            t.`Document_id` = r.`Document_id`,
            t.`Document_no` = r.`Document_no`,
            t.`Document_date` = r.`Document_date`,
            t.`updated_by` = CASE
                                WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'purchase'
                                ELSE CONCAT(t.`updated_by`, '; ', 'purchase')
                             END,
            t.`updated_at` = CURRENT_TIMESTAMP;
    END IF;

END$$

/* Совместимость с именем из задания (с опечаткой). */
CREATE DEFINER=`bot_ERP`@`%` PROCEDURE bot_purhaser(
    IN purch_purch INT,
    IN purch_byed INT,
    IN purch_manuf INT,
    IN prod_rework INT,
    IN purch_return INT,
    IN purch_cost BIGINT
)
SQL SECURITY DEFINER
BEGIN
    CALL bot_purchaser(purch_purch, purch_byed, purch_manuf, prod_rework, purch_return, purch_cost);
END$$

CREATE DEFINER=`bot_ERP`@`%` PROCEDURE bot_purcaser(
    IN purch_purch INT,
    IN purch_byed INT,
    IN purch_manuf INT,
    IN prod_rework INT,
    IN purch_return INT,
    IN purch_cost BIGINT
)
SQL SECURITY DEFINER
BEGIN
    CALL bot_purchaser(purch_purch, purch_byed, purch_manuf, prod_rework, purch_return, purch_cost);
END$$

CREATE DEFINER=`bot_ERP`@`%` PROCEDURE bot_shopfloor(
    IN prod_kit INT,
    IN prod_assembled INT,
    IN prod_prod INT,
    IN prod_manuf INT,
    IN prod_purch INT,
    IN prod_shipped INT,
    IN prod_loss INT,
    IN prod_rework INT,
    IN prod_return INT
)
SQL SECURITY DEFINER
BEGIN
    DECLARE v_projects TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

    SELECT NULLIF(TRIM(MAX(CASE WHEN `variable_name` = 'Projects' THEN `text_parameter` END)), '')
      INTO v_projects
    FROM `bot_parameters`;

    /* change: неопределенные или спорные строки -> собственное производство */
    IF COALESCE(prod_purch, 0) > 0 THEN
        UPDATE `Transactions` t
        INNER JOIN (
            SELECT z.id
            FROM `Transactions` z
            WHERE z.`type` = 'change'
              AND z.`Status_transaction` = 'В ожидании'
              AND z.`Status_warehouse` = 'Новая'
              AND (
                  z.`Recommend_purchprod` IS NULL
                  OR (z.`Recommend_purchprod` = 'В закупку' AND z.`Order_purch` = 'В собственное производство')
              )
              AND (
                    v_projects IS NULL
                 OR TRIM(COALESCE(v_projects, '')) = ''
                 OR FIND_IN_SET(
                      TRIM(COALESCE(CAST(z.`Project` AS CHAR CHARACTER SET utf8mb4), '')) COLLATE utf8mb4_unicode_ci,
                      REPLACE(v_projects, ', ', ',') COLLATE utf8mb4_unicode_ci
                    ) > 0
              )
            ORDER BY RAND()
            LIMIT prod_purch
        ) r ON r.id = t.id
        SET t.`Order_purch` = 'В собственное производство',
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
              AND z.`Status_warehouse` = 'Новая'
              AND z.`Recommend_purchprod` = 'В собственное производство'
              AND (
                    v_projects IS NULL
                 OR TRIM(COALESCE(v_projects, '')) = ''
                 OR FIND_IN_SET(
                      TRIM(COALESCE(CAST(z.`Project` AS CHAR CHARACTER SET utf8mb4), '')) COLLATE utf8mb4_unicode_ci,
                      REPLACE(v_projects, ', ', ',') COLLATE utf8mb4_unicode_ci
                    ) > 0
              )
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

    /* change: производство перекидывает рекомендованное производство в закупку */
    IF COALESCE(prod_purch, 0) > 0 THEN
        UPDATE `Transactions` t
        INNER JOIN (
            SELECT z.id
            FROM `Transactions` z
            WHERE z.`type` = 'change'
              AND z.`Status_transaction` = 'В ожидании'
              AND z.`Status_warehouse` = 'Новая'
              AND z.`Recommend_purchprod` = 'В собственное производство'
              AND (
                    v_projects IS NULL
                 OR TRIM(COALESCE(v_projects, '')) = ''
                 OR FIND_IN_SET(
                      TRIM(COALESCE(CAST(z.`Project` AS CHAR CHARACTER SET utf8mb4), '')) COLLATE utf8mb4_unicode_ci,
                      REPLACE(v_projects, ', ', ',') COLLATE utf8mb4_unicode_ci
                    ) > 0
              )
            ORDER BY RAND()
            LIMIT prod_purch
        ) r ON r.id = t.id
        SET t.`Order_purch` = 'В закупке',
            t.`linked_transaction` = CASE
                WHEN t.`linked_transaction` IS NULL OR TRIM(COALESCE(t.`linked_transaction`, '')) = '' THEN CAST(t.id AS CHAR)
                ELSE CONCAT(TRIM(t.`linked_transaction`), '; ', t.id)
            END,
            t.`updated_by` = CASE WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'bot_shopfloor' ELSE CONCAT(t.`updated_by`, '; ', 'bot_shopfloor') END,
            t.`updated_at` = CURRENT_TIMESTAMP;
    END IF;

    /* change/move: доработка -> изготовлено */
    IF COALESCE(prod_rework, 0) > 0 THEN
        UPDATE `Transactions` t
        INNER JOIN (
            SELECT z.id
            FROM `Transactions` z
            WHERE z.`type` = 'change'
              AND z.`Status_transaction` = 'В ожидании'
              AND z.`where_to` = 'склад'
              AND z.`Status_warehouse` = 'Доработка'
              AND (
                    v_projects IS NULL
                 OR TRIM(COALESCE(v_projects, '')) = ''
                 OR FIND_IN_SET(
                      TRIM(COALESCE(CAST(z.`Project` AS CHAR CHARACTER SET utf8mb4), '')) COLLATE utf8mb4_unicode_ci,
                      REPLACE(v_projects, ', ', ',') COLLATE utf8mb4_unicode_ci
                    ) > 0
              )
            ORDER BY RAND()
            LIMIT prod_rework
        ) r ON r.id = t.id
        SET t.`Order_prod` = 'Изготовлено',
            t.`linked_transaction` = CASE
                WHEN t.`linked_transaction` IS NULL OR TRIM(COALESCE(t.`linked_transaction`, '')) = '' THEN CAST(t.id AS CHAR)
                ELSE CONCAT(TRIM(t.`linked_transaction`), '; ', t.id)
            END,
            t.`updated_by` = CASE WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'bot_shopfloor' ELSE CONCAT(t.`updated_by`, '; ', 'bot_shopfloor') END,
            t.`updated_at` = CURRENT_TIMESTAMP;

        UPDATE `Transactions` t
        INNER JOIN (
            SELECT z.id
            FROM `Transactions` z
            WHERE z.`type` = 'move'
              AND z.`Status_transaction` = 'В ожидании'
              AND z.`where_to` = 'доработка'
              AND (
                    v_projects IS NULL
                 OR TRIM(COALESCE(v_projects, '')) = ''
                 OR FIND_IN_SET(
                      TRIM(COALESCE(CAST(z.`Project` AS CHAR CHARACTER SET utf8mb4), '')) COLLATE utf8mb4_unicode_ci,
                      REPLACE(v_projects, ', ', ',') COLLATE utf8mb4_unicode_ci
                    ) > 0
              )
            ORDER BY RAND()
            LIMIT prod_rework
        ) r ON r.id = t.id
        SET t.`Order_prod` = 'Изготовлено',
            t.`linked_transaction` = CASE
                WHEN t.`linked_transaction` IS NULL OR TRIM(COALESCE(t.`linked_transaction`, '')) = '' THEN CAST(t.id AS CHAR)
                ELSE CONCAT(TRIM(t.`linked_transaction`), '; ', t.id)
            END,
            t.`updated_by` = CASE WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'bot_shopfloor' ELSE CONCAT(t.`updated_by`, '; ', 'bot_shopfloor') END,
            t.`updated_at` = CURRENT_TIMESTAMP;
    END IF;

    /* change: уточнения по производству -> принято в изготовление */
    IF COALESCE(prod_prod, 0) > 0 THEN
        UPDATE `Transactions` t
        INNER JOIN (
            SELECT z.id
            FROM `Transactions` z
            WHERE z.`type` = 'change'
              AND z.`Status_transaction` = 'В ожидании'
              AND z.`Status_warehouse` = 'Новая'
              AND z.`Recommend_purchprod` = 'Уточнить кол-во в производстве'
              AND (
                    v_projects IS NULL
                 OR TRIM(COALESCE(v_projects, '')) = ''
                 OR FIND_IN_SET(
                      TRIM(COALESCE(CAST(z.`Project` AS CHAR CHARACTER SET utf8mb4), '')) COLLATE utf8mb4_unicode_ci,
                      REPLACE(v_projects, ', ', ',') COLLATE utf8mb4_unicode_ci
                    ) > 0
              )
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

        UPDATE `Transactions` t
        INNER JOIN (
            SELECT z.id
            FROM `Transactions` z
            WHERE z.`type` = 'change'
              AND z.`Status_transaction` = 'В ожидании'
              AND z.`Status_warehouse` = 'Новая'
              AND z.`Recommend_purchprod` = 'Уточнить ревизию в производстве'
              AND (
                    v_projects IS NULL
                 OR TRIM(COALESCE(v_projects, '')) = ''
                 OR FIND_IN_SET(
                      TRIM(COALESCE(CAST(z.`Project` AS CHAR CHARACTER SET utf8mb4), '')) COLLATE utf8mb4_unicode_ci,
                      REPLACE(v_projects, ', ', ',') COLLATE utf8mb4_unicode_ci
                    ) > 0
              )
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
              AND (
                    v_projects IS NULL
                 OR TRIM(COALESCE(v_projects, '')) = ''
                 OR FIND_IN_SET(
                      TRIM(COALESCE(CAST(z.`Project` AS CHAR CHARACTER SET utf8mb4), '')) COLLATE utf8mb4_unicode_ci,
                      REPLACE(v_projects, ', ', ',') COLLATE utf8mb4_unicode_ci
                    ) > 0
              )
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
              AND z.`Order_wh` = 'Списано со склада'
              AND (
                    v_projects IS NULL
                 OR TRIM(COALESCE(v_projects, '')) = ''
                 OR FIND_IN_SET(
                      TRIM(COALESCE(CAST(z.`Project` AS CHAR CHARACTER SET utf8mb4), '')) COLLATE utf8mb4_unicode_ci,
                      REPLACE(v_projects, ', ', ',') COLLATE utf8mb4_unicode_ci
                    ) > 0
              )
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
              AND z.`where_to` = 'изделие'
              AND (
                    v_projects IS NULL
                 OR TRIM(COALESCE(v_projects, '')) = ''
                 OR FIND_IN_SET(
                      TRIM(COALESCE(CAST(z.`Project` AS CHAR CHARACTER SET utf8mb4), '')) COLLATE utf8mb4_unicode_ci,
                      REPLACE(v_projects, ', ', ',') COLLATE utf8mb4_unicode_ci
                    ) > 0
              )
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
              AND (
                    v_projects IS NULL
                 OR TRIM(COALESCE(v_projects, '')) = ''
                 OR FIND_IN_SET(
                      TRIM(COALESCE(CAST(z.`Project` AS CHAR CHARACTER SET utf8mb4), '')) COLLATE utf8mb4_unicode_ci,
                      REPLACE(v_projects, ', ', ',') COLLATE utf8mb4_unicode_ci
                    ) > 0
              )
            ORDER BY RAND()
            LIMIT prod_shipped
        ) r ON r.id = t.id
        SET t.`Order_prod` = 'Упаковано',
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
              AND (
                    v_projects IS NULL
                 OR TRIM(COALESCE(v_projects, '')) = ''
                 OR FIND_IN_SET(
                      TRIM(COALESCE(CAST(z.`Project` AS CHAR CHARACTER SET utf8mb4), '')) COLLATE utf8mb4_unicode_ci,
                      REPLACE(v_projects, ', ', ',') COLLATE utf8mb4_unicode_ci
                    ) > 0
              )
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

    /* move: цех -> склад, вернуть на склад */
    IF COALESCE(prod_return, 0) > 0 THEN
        UPDATE `Transactions` t
        INNER JOIN (
            SELECT z.id
            FROM `Transactions` z
            WHERE z.`type` = 'move'
              AND z.`Status_transaction` = 'В ожидании'
              AND z.`where_from` = 'цех'
              AND z.`where_to` = 'склад'
              AND (
                    v_projects IS NULL
                 OR TRIM(COALESCE(v_projects, '')) = ''
                 OR FIND_IN_SET(
                      TRIM(COALESCE(CAST(z.`Project` AS CHAR CHARACTER SET utf8mb4), '')) COLLATE utf8mb4_unicode_ci,
                      REPLACE(v_projects, ', ', ',') COLLATE utf8mb4_unicode_ci
                    ) > 0
              )
            ORDER BY RAND()
            LIMIT prod_return
        ) r ON r.id = t.id
        SET t.`Order_prod` = 'Вернуть на склад',
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
    DECLARE v_projects TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

    SELECT NULLIF(TRIM(MAX(CASE WHEN `variable_name` = 'Projects' THEN `text_parameter` END)), '')
      INTO v_projects
    FROM `bot_parameters`;

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
              AND (
                    v_projects IS NULL
                 OR TRIM(COALESCE(v_projects, '')) = ''
                 OR FIND_IN_SET(
                      TRIM(COALESCE(CAST(z.`Project` AS CHAR CHARACTER SET utf8mb4), '')) COLLATE utf8mb4_unicode_ci,
                      REPLACE(v_projects, ', ', ',') COLLATE utf8mb4_unicode_ci
                    ) > 0
              )
            ORDER BY RAND()
            LIMIT wh_purch
        ) r ON r.id = t.id
        SET t.`Order_wh` = 'Принято на склад',
            t.`updated_by` = CASE WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'warehouse' ELSE CONCAT(t.`updated_by`, '; ', 'warehouse') END,
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
              AND (
                    v_projects IS NULL
                 OR TRIM(COALESCE(v_projects, '')) = ''
                 OR FIND_IN_SET(
                      TRIM(COALESCE(CAST(z.`Project` AS CHAR CHARACTER SET utf8mb4), '')) COLLATE utf8mb4_unicode_ci,
                      REPLACE(v_projects, ', ', ',') COLLATE utf8mb4_unicode_ci
                    ) > 0
              )
            ORDER BY RAND()
            LIMIT wh_manuf
        ) r ON r.id = t.id
        SET t.`Order_wh` = 'Принято на склад',
            t.`updated_by` = CASE WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'warehouse' ELSE CONCAT(t.`updated_by`, '; ', 'warehouse') END,
            t.`updated_at` = CURRENT_TIMESTAMP;
    END IF;

    IF COALESCE(wh_return, 0) > 0 THEN
        UPDATE `Transactions` t
        INNER JOIN (
            SELECT z.id
            FROM `Transactions` z
            WHERE z.`type` = 'move'
              AND z.`Status_transaction` = 'В ожидании'
              AND z.`Status_warehouse` IN ('Утилизация', 'Сборка', 'Упаковка', 'Доработка')
              AND (
                  z.`Order_prod` = 'Вернуть на склад'
                  OR (z.`Order_prod` = 'Изготовлено' AND z.`Order_OTK` = 'Принято')
              )
              AND (
                    v_projects IS NULL
                 OR TRIM(COALESCE(v_projects, '')) = ''
                 OR FIND_IN_SET(
                      TRIM(COALESCE(CAST(z.`Project` AS CHAR CHARACTER SET utf8mb4), '')) COLLATE utf8mb4_unicode_ci,
                      REPLACE(v_projects, ', ', ',') COLLATE utf8mb4_unicode_ci
                    ) > 0
              )
            ORDER BY RAND()
            LIMIT wh_return
        ) r ON r.id = t.id
        SET t.`Order_wh` = 'Принято на склад',
            t.`updated_by` = CASE WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'warehouse' ELSE CONCAT(t.`updated_by`, '; ', 'warehouse') END,
            t.`updated_at` = CURRENT_TIMESTAMP;
    END IF;

    IF COALESCE(wh_kit, 0) > 0 THEN
        UPDATE `Transactions` t
        INNER JOIN (
            SELECT z.id
            FROM `Transactions` z
            WHERE z.`Status_transaction` = 'В ожидании'
              AND z.`Status_warehouse` = 'Комплектация'
              AND (
                    v_projects IS NULL
                 OR TRIM(COALESCE(v_projects, '')) = ''
                 OR FIND_IN_SET(
                      TRIM(COALESCE(CAST(z.`Project` AS CHAR CHARACTER SET utf8mb4), '')) COLLATE utf8mb4_unicode_ci,
                      REPLACE(v_projects, ', ', ',') COLLATE utf8mb4_unicode_ci
                    ) > 0
              )
            ORDER BY RAND()
            LIMIT wh_kit
        ) r ON r.id = t.id
        SET t.`Order_wh` = 'Списано со склада',
            t.`updated_by` = CASE WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'warehouse' ELSE CONCAT(t.`updated_by`, '; ', 'warehouse') END,
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
    DECLARE v_projects TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

    SELECT NULLIF(TRIM(MAX(CASE WHEN `variable_name` = 'Projects' THEN `text_parameter` END)), '')
      INTO v_projects
    FROM `bot_parameters`;

    IF COALESCE(OTK_manuf, 0) > 0 THEN
        UPDATE `Transactions` t
        INNER JOIN (
            SELECT z.id
            FROM `Transactions` z
            WHERE z.`type` = 'change'
              AND z.`Status_transaction` = 'В ожидании'
              AND z.`Order_prod` = 'Изготовлено'
              AND (
                    v_projects IS NULL
                 OR TRIM(COALESCE(v_projects, '')) = ''
                 OR FIND_IN_SET(
                      TRIM(COALESCE(CAST(z.`Project` AS CHAR CHARACTER SET utf8mb4), '')) COLLATE utf8mb4_unicode_ci,
                      REPLACE(v_projects, ', ', ',') COLLATE utf8mb4_unicode_ci
                    ) > 0
              )
            ORDER BY RAND()
            LIMIT OTK_manuf
        ) r ON r.id = t.id
        SET t.`Order_OTK` = 'Принято',
            t.`updated_by` = CASE WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'OTK' ELSE CONCAT(t.`updated_by`, '; ', 'OTK') END,
            t.`updated_at` = CURRENT_TIMESTAMP;
    END IF;

    IF COALESCE(OTK_assembly, 0) > 0 THEN
        UPDATE `Transactions` t
        INNER JOIN (
            SELECT z.id
            FROM `Transactions` z
            WHERE z.`type` = 'move'
              AND z.`Status_transaction` = 'В ожидании'
              AND z.`Order_prod` = 'Изготовлено'
              AND (
                    v_projects IS NULL
                 OR TRIM(COALESCE(v_projects, '')) = ''
                 OR FIND_IN_SET(
                      TRIM(COALESCE(CAST(z.`Project` AS CHAR CHARACTER SET utf8mb4), '')) COLLATE utf8mb4_unicode_ci,
                      REPLACE(v_projects, ', ', ',') COLLATE utf8mb4_unicode_ci
                    ) > 0
              )
            ORDER BY RAND()
            LIMIT OTK_assembly
        ) r ON r.id = t.id
        SET t.`Order_OTK` = 'Принято',
            t.`updated_by` = CASE WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'OTK' ELSE CONCAT(t.`updated_by`, '; ', 'OTK') END,
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
              AND (
                    v_projects IS NULL
                 OR TRIM(COALESCE(v_projects, '')) = ''
                 OR FIND_IN_SET(
                      TRIM(COALESCE(CAST(z.`Project` AS CHAR CHARACTER SET utf8mb4), '')) COLLATE utf8mb4_unicode_ci,
                      REPLACE(v_projects, ', ', ',') COLLATE utf8mb4_unicode_ci
                    ) > 0
              )
            ORDER BY RAND()
            LIMIT OTK_shipped
        ) r ON r.id = t.id
        SET t.`Order_OTK` = 'Принято',
            t.`updated_by` = CASE WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'OTK' ELSE CONCAT(t.`updated_by`, '; ', 'OTK') END,
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
              AND (
                    v_projects IS NULL
                 OR TRIM(COALESCE(v_projects, '')) = ''
                 OR FIND_IN_SET(
                      TRIM(COALESCE(CAST(z.`Project` AS CHAR CHARACTER SET utf8mb4), '')) COLLATE utf8mb4_unicode_ci,
                      REPLACE(v_projects, ', ', ',') COLLATE utf8mb4_unicode_ci
                    ) > 0
              )
            ORDER BY RAND()
            LIMIT OTK_loss
        ) r ON r.id = t.id
        SET t.`Order_OTK` = 'Забраковано',
            t.`updated_by` = CASE WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'OTK' ELSE CONCAT(t.`updated_by`, '; ', 'OTK') END,
            t.`updated_at` = CURRENT_TIMESTAMP;
    END IF;
END$$

CREATE DEFINER=`bot_ERP`@`%` PROCEDURE bot_supervisor(
    IN sv_choice INT,
    IN sv_replace INT,
    IN replace_to VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci
)
SQL SECURITY DEFINER
BEGIN
    DECLARE v_done INT DEFAULT 0;
    DECLARE v_tx_id BIGINT DEFAULT NULL;
    DECLARE v_projects TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

    DECLARE cur_replace_wh CURSOR FOR
        SELECT t.`id`
        FROM `Transactions` t
        WHERE t.`type` = 'move'
          AND t.`Status_transaction` = 'В ожидании'
          AND t.`Order_sv` = 'Заменить со склада'
          AND t.`Replace_to` IS NOT NULL
          AND TRIM(COALESCE(t.`Replace_to`, '')) <> ''
          AND (
                v_projects IS NULL
             OR TRIM(COALESCE(v_projects, '')) = ''
             OR FIND_IN_SET(
                  TRIM(COALESCE(CAST(t.`Project` AS CHAR CHARACTER SET utf8mb4), '')) COLLATE utf8mb4_unicode_ci,
                  REPLACE(v_projects, ', ', ',') COLLATE utf8mb4_unicode_ci
                ) > 0
          )
        ORDER BY t.`id`;

    DECLARE cur_replace_new CURSOR FOR
        SELECT t.`id`
        FROM `Transactions` t
        WHERE t.`type` IN ('change', 'move')
          AND t.`Status_transaction` = 'В ожидании'
          AND t.`Order_sv` = 'Заменить и восполнить'
          AND t.`Replace_to` IS NOT NULL
          AND TRIM(COALESCE(t.`Replace_to`, '')) <> ''
          AND (
                v_projects IS NULL
             OR TRIM(COALESCE(v_projects, '')) = ''
             OR FIND_IN_SET(
                  TRIM(COALESCE(CAST(t.`Project` AS CHAR CHARACTER SET utf8mb4), '')) COLLATE utf8mb4_unicode_ci,
                  REPLACE(v_projects, ', ', ',') COLLATE utf8mb4_unicode_ci
                ) > 0
          )
        ORDER BY t.`id`;

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = 1;

    SELECT NULLIF(TRIM(MAX(CASE WHEN `variable_name` = 'Projects' THEN `text_parameter` END)), '')
      INTO v_projects
    FROM `bot_parameters`;

    IF COALESCE(sv_choice, 0) > 0 THEN
        UPDATE `Transactions` t
        INNER JOIN (
            SELECT z.`id`
            FROM `Transactions` z
            WHERE z.`Status_transaction` = 'В ожидании'
              AND z.`Recommend_wh` IS NOT NULL
              AND z.`Recommend_wh` LIKE '%разбить%'
              AND (
                    v_projects IS NULL
                 OR TRIM(COALESCE(v_projects, '')) = ''
                 OR FIND_IN_SET(
                      TRIM(COALESCE(CAST(z.`Project` AS CHAR CHARACTER SET utf8mb4), '')) COLLATE utf8mb4_unicode_ci,
                      REPLACE(v_projects, ', ', ',') COLLATE utf8mb4_unicode_ci
                    ) > 0
              )
            ORDER BY RAND()
            LIMIT sv_choice
        ) r ON r.id = t.id
        SET t.`Order_sv` = 'Разбить',
            t.`updated_by` = CASE WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'supervisor' ELSE CONCAT(t.`updated_by`, '; ', 'supervisor') END,
            t.`updated_at` = CURRENT_TIMESTAMP;

        UPDATE `Transactions` t
        INNER JOIN (
            SELECT z.`id`
            FROM `Transactions` z
            WHERE z.`Status_transaction` = 'В ожидании'
              AND z.`Recommend_wh` IS NOT NULL
              AND z.`Recommend_wh` LIKE '%забраковать%'
              AND (
                    v_projects IS NULL
                 OR TRIM(COALESCE(v_projects, '')) = ''
                 OR FIND_IN_SET(
                      TRIM(COALESCE(CAST(z.`Project` AS CHAR CHARACTER SET utf8mb4), '')) COLLATE utf8mb4_unicode_ci,
                      REPLACE(v_projects, ', ', ',') COLLATE utf8mb4_unicode_ci
                    ) > 0
              )
            ORDER BY RAND()
            LIMIT sv_choice
        ) r ON r.id = t.id
        SET t.`Order_sv` = 'Забраковать',
            t.`updated_by` = CASE WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'supervisor' ELSE CONCAT(t.`updated_by`, '; ', 'supervisor') END,
            t.`updated_at` = CURRENT_TIMESTAMP;

        UPDATE `Transactions` t
        INNER JOIN (
            SELECT z.`id`
            FROM `Transactions` z
            WHERE z.`Status_transaction` = 'В ожидании'
              AND z.`Recommend_wh` IS NOT NULL
              AND z.`Recommend_wh` LIKE '%отменить%'
              AND (
                    v_projects IS NULL
                 OR TRIM(COALESCE(v_projects, '')) = ''
                 OR FIND_IN_SET(
                      TRIM(COALESCE(CAST(z.`Project` AS CHAR CHARACTER SET utf8mb4), '')) COLLATE utf8mb4_unicode_ci,
                      REPLACE(v_projects, ', ', ',') COLLATE utf8mb4_unicode_ci
                    ) > 0
              )
            ORDER BY RAND()
            LIMIT sv_choice
        ) r ON r.id = t.id
        SET t.`Order_sv` = 'Отменить',
            t.`updated_by` = CASE WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'supervisor' ELSE CONCAT(t.`updated_by`, '; ', 'supervisor') END,
            t.`updated_at` = CURRENT_TIMESTAMP;

        UPDATE `Transactions` t
        INNER JOIN (
            SELECT z.`id`
            FROM `Transactions` z
            WHERE z.`Status_transaction` = 'В ожидании'
              AND z.`Recommend_wh` IS NOT NULL
              AND z.`Recommend_wh` LIKE '%доработать запас%'
              AND (
                    v_projects IS NULL
                 OR TRIM(COALESCE(v_projects, '')) = ''
                 OR FIND_IN_SET(
                      TRIM(COALESCE(CAST(z.`Project` AS CHAR CHARACTER SET utf8mb4), '')) COLLATE utf8mb4_unicode_ci,
                      REPLACE(v_projects, ', ', ',') COLLATE utf8mb4_unicode_ci
                    ) > 0
              )
            ORDER BY RAND()
            LIMIT sv_choice
        ) r ON r.id = t.id
        SET t.`Order_sv` = 'Доработать запас',
            t.`updated_by` = CASE WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'supervisor' ELSE CONCAT(t.`updated_by`, '; ', 'supervisor') END,
            t.`updated_at` = CURRENT_TIMESTAMP;
    END IF;

    SET v_done = 0;
    OPEN cur_replace_wh;
    replace_wh_loop: LOOP
        FETCH cur_replace_wh INTO v_tx_id;
        IF v_done = 1 THEN
            LEAVE replace_wh_loop;
        END IF;
        CALL replace_wh(v_tx_id);
    END LOOP;
    CLOSE cur_replace_wh;

    SET v_done = 0;
    OPEN cur_replace_new;
    replace_new_loop: LOOP
        FETCH cur_replace_new INTO v_tx_id;
        IF v_done = 1 THEN
            LEAVE replace_new_loop;
        END IF;
        CALL replace_new(v_tx_id);
    END LOOP;
    CLOSE cur_replace_new;

    IF COALESCE(sv_replace, 0) > 0 AND replace_to IS NOT NULL AND TRIM(COALESCE(replace_to, '')) <> '' THEN
        UPDATE `Transactions` t
        INNER JOIN (
            SELECT z.`id`
            FROM `Transactions` z
            WHERE z.`type` = 'move'
              AND z.`Status_transaction` = 'В ожидании'
              AND (
                    v_projects IS NULL
                 OR TRIM(COALESCE(v_projects, '')) = ''
                 OR FIND_IN_SET(
                      TRIM(COALESCE(CAST(z.`Project` AS CHAR CHARACTER SET utf8mb4), '')) COLLATE utf8mb4_unicode_ci,
                      REPLACE(v_projects, ', ', ',') COLLATE utf8mb4_unicode_ci
                    ) > 0
              )
            ORDER BY RAND()
            LIMIT sv_replace
        ) r ON r.id = t.id
        SET t.`Replace_to` = replace_to,
            t.`Order_sv` = 'Заменить со склада',
            t.`updated_by` = CASE WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'supervisor' ELSE CONCAT(t.`updated_by`, '; ', 'supervisor') END,
            t.`updated_at` = CURRENT_TIMESTAMP;

        UPDATE `Transactions` t
        INNER JOIN (
            SELECT z.`id`
            FROM `Transactions` z
            WHERE z.`Status_transaction` = 'В ожидании'
              AND (
                    v_projects IS NULL
                 OR TRIM(COALESCE(v_projects, '')) = ''
                 OR FIND_IN_SET(
                      TRIM(COALESCE(CAST(z.`Project` AS CHAR CHARACTER SET utf8mb4), '')) COLLATE utf8mb4_unicode_ci,
                      REPLACE(v_projects, ', ', ',') COLLATE utf8mb4_unicode_ci
                    ) > 0
              )
            ORDER BY RAND()
            LIMIT sv_replace
        ) r ON r.id = t.id
        SET t.`Replace_to` = replace_to,
            t.`Order_sv` = 'Заменить и восполнить',
            t.`updated_by` = CASE WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'supervisor' ELSE CONCAT(t.`updated_by`, '; ', 'supervisor') END,
            t.`updated_at` = CURRENT_TIMESTAMP;
    END IF;
END$$

CREATE DEFINER=`bot_ERP`@`%` PROCEDURE bot_call()
SQL SECURITY DEFINER
BEGIN
    DECLARE exp_row_count INT;
    DECLARE exp_approve INT;

    DECLARE purch_purch INT;
    DECLARE purch_byed INT;
    DECLARE purch_manuf INT;
    DECLARE prod_rework INT;
    DECLARE purch_return INT;
    DECLARE purch_cost BIGINT;

    DECLARE prod_kit INT;
    DECLARE prod_assembled INT;
    DECLARE prod_prod INT;
    DECLARE prod_manuf INT;
    DECLARE prod_purch INT;
    DECLARE prod_shipped INT;
    DECLARE prod_loss INT;
    DECLARE prod_return INT;

    DECLARE wh_purch INT;
    DECLARE wh_manuf INT;
    DECLARE wh_return INT;
    DECLARE wh_kit INT;

    DECLARE OTK_manuf INT;
    DECLARE OTK_assembly INT;
    DECLARE OTK_shipped INT;
    DECLARE OTK_loss INT;

    DECLARE sv_choice INT;
    DECLARE sv_replace INT;
    DECLARE replace_to VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
    DECLARE v_projects TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

    SELECT NULLIF(TRIM(MAX(CASE WHEN `variable_name` = 'Projects' THEN `text_parameter` END)), '')
      INTO v_projects
    FROM `bot_parameters`;

    SET exp_row_count  = COALESCE((SELECT FLOOR(COALESCE(bp.`value_min`, 5) + RAND() * GREATEST(COALESCE(bp.`value_max`, 15) - COALESCE(bp.`value_min`, 5) + 1, 1)) FROM `bot_parameters` bp WHERE bp.`variable_name` = 'exp_row_count' LIMIT 1), FLOOR(5 + RAND() * 11));
    SET exp_approve    = COALESCE((SELECT FLOOR(COALESCE(bp.`value_min`, 5) + RAND() * GREATEST(COALESCE(bp.`value_max`, 15) - COALESCE(bp.`value_min`, 5) + 1, 1)) FROM `bot_parameters` bp WHERE bp.`variable_name` = 'exp_approve' LIMIT 1), FLOOR(5 + RAND() * 11));

    SET purch_purch    = COALESCE((SELECT FLOOR(COALESCE(bp.`value_min`, 5) + RAND() * GREATEST(COALESCE(bp.`value_max`, 15) - COALESCE(bp.`value_min`, 5) + 1, 1)) FROM `bot_parameters` bp WHERE bp.`variable_name` = 'purch_purch' LIMIT 1), FLOOR(5 + RAND() * 11));
    SET purch_byed     = COALESCE((SELECT FLOOR(COALESCE(bp.`value_min`, 5) + RAND() * GREATEST(COALESCE(bp.`value_max`, 15) - COALESCE(bp.`value_min`, 5) + 1, 1)) FROM `bot_parameters` bp WHERE bp.`variable_name` = 'purch_byed' LIMIT 1), FLOOR(5 + RAND() * 11));
    SET purch_manuf    = COALESCE((SELECT FLOOR(COALESCE(bp.`value_min`, 0) + RAND() * GREATEST(COALESCE(bp.`value_max`, 1) - COALESCE(bp.`value_min`, 0) + 1, 1)) FROM `bot_parameters` bp WHERE bp.`variable_name` = 'purch_manuf' LIMIT 1), FLOOR(0 + RAND() * 2));
    SET prod_rework    = COALESCE((SELECT FLOOR(COALESCE(bp.`value_min`, 0) + RAND() * GREATEST(COALESCE(bp.`value_max`, 1) - COALESCE(bp.`value_min`, 0) + 1, 1)) FROM `bot_parameters` bp WHERE bp.`variable_name` = 'prod_rework' LIMIT 1), FLOOR(0 + RAND() * 2));
    SET purch_return   = COALESCE((SELECT FLOOR(COALESCE(bp.`value_min`, 0) + RAND() * GREATEST(COALESCE(bp.`value_max`, 1) - COALESCE(bp.`value_min`, 0) + 1, 1)) FROM `bot_parameters` bp WHERE bp.`variable_name` = 'purch_return' LIMIT 1), FLOOR(0 + RAND() * 2));
    SET purch_cost     = COALESCE((SELECT FLOOR(COALESCE(bp.`value_min`, 5000) + RAND() * GREATEST(COALESCE(bp.`value_max`, 150000) - COALESCE(bp.`value_min`, 5000) + 1, 1)) FROM `bot_parameters` bp WHERE bp.`variable_name` = 'purch_cost' LIMIT 1), FLOOR(5000 + RAND() * 145001));

    SET prod_kit       = COALESCE((SELECT FLOOR(COALESCE(bp.`value_min`, 5) + RAND() * GREATEST(COALESCE(bp.`value_max`, 15) - COALESCE(bp.`value_min`, 5) + 1, 1)) FROM `bot_parameters` bp WHERE bp.`variable_name` = 'prod_kit' LIMIT 1), FLOOR(5 + RAND() * 11));
    SET prod_assembled = COALESCE((SELECT FLOOR(COALESCE(bp.`value_min`, 3) + RAND() * GREATEST(COALESCE(bp.`value_max`, 14) - COALESCE(bp.`value_min`, 3) + 1, 1)) FROM `bot_parameters` bp WHERE bp.`variable_name` = 'prod_assembled' LIMIT 1), FLOOR(3 + RAND() * 12));
    SET prod_prod      = COALESCE((SELECT FLOOR(COALESCE(bp.`value_min`, 1) + RAND() * GREATEST(COALESCE(bp.`value_max`, 4) - COALESCE(bp.`value_min`, 1) + 1, 1)) FROM `bot_parameters` bp WHERE bp.`variable_name` = 'prod_prod' LIMIT 1), FLOOR(1 + RAND() * 4));
    SET prod_manuf     = COALESCE((SELECT FLOOR(COALESCE(bp.`value_min`, 1) + RAND() * GREATEST(COALESCE(bp.`value_max`, 4) - COALESCE(bp.`value_min`, 1) + 1, 1)) FROM `bot_parameters` bp WHERE bp.`variable_name` = 'prod_manuf' LIMIT 1), FLOOR(1 + RAND() * 4));
    SET prod_purch     = COALESCE((SELECT FLOOR(COALESCE(bp.`value_min`, 0) + RAND() * GREATEST(COALESCE(bp.`value_max`, 1) - COALESCE(bp.`value_min`, 0) + 1, 1)) FROM `bot_parameters` bp WHERE bp.`variable_name` = 'prod_purch' LIMIT 1), FLOOR(0 + RAND() * 2));
    SET prod_shipped   = COALESCE((SELECT FLOOR(COALESCE(bp.`value_min`, 0) + RAND() * GREATEST(COALESCE(bp.`value_max`, 1) - COALESCE(bp.`value_min`, 0) + 1, 1)) FROM `bot_parameters` bp WHERE bp.`variable_name` = 'prod_shipped' LIMIT 1), FLOOR(0 + RAND() * 2));
    SET prod_loss      = COALESCE((SELECT FLOOR(COALESCE(bp.`value_min`, 0) + RAND() * GREATEST(COALESCE(bp.`value_max`, 1) - COALESCE(bp.`value_min`, 0) + 1, 1)) FROM `bot_parameters` bp WHERE bp.`variable_name` = 'prod_loss' LIMIT 1), FLOOR(0 + RAND() * 2));
    SET prod_return    = COALESCE((SELECT FLOOR(COALESCE(bp.`value_min`, 0) + RAND() * GREATEST(COALESCE(bp.`value_max`, 1) - COALESCE(bp.`value_min`, 0) + 1, 1)) FROM `bot_parameters` bp WHERE bp.`variable_name` = 'prod_return' LIMIT 1), FLOOR(0 + RAND() * 2));

    SET wh_purch       = COALESCE((SELECT FLOOR(COALESCE(bp.`value_min`, 5) + RAND() * GREATEST(COALESCE(bp.`value_max`, 15) - COALESCE(bp.`value_min`, 5) + 1, 1)) FROM `bot_parameters` bp WHERE bp.`variable_name` = 'wh_purch' LIMIT 1), FLOOR(5 + RAND() * 11));
    SET wh_manuf       = COALESCE((SELECT FLOOR(COALESCE(bp.`value_min`, 5) + RAND() * GREATEST(COALESCE(bp.`value_max`, 15) - COALESCE(bp.`value_min`, 5) + 1, 1)) FROM `bot_parameters` bp WHERE bp.`variable_name` = 'wh_manuf' LIMIT 1), FLOOR(5 + RAND() * 11));
    SET wh_return      = COALESCE((SELECT FLOOR(COALESCE(bp.`value_min`, 5) + RAND() * GREATEST(COALESCE(bp.`value_max`, 15) - COALESCE(bp.`value_min`, 5) + 1, 1)) FROM `bot_parameters` bp WHERE bp.`variable_name` = 'wh_return' LIMIT 1), FLOOR(5 + RAND() * 11));
    SET wh_kit         = COALESCE((SELECT FLOOR(COALESCE(bp.`value_min`, 5) + RAND() * GREATEST(COALESCE(bp.`value_max`, 15) - COALESCE(bp.`value_min`, 5) + 1, 1)) FROM `bot_parameters` bp WHERE bp.`variable_name` = 'wh_kit' LIMIT 1), FLOOR(5 + RAND() * 11));

    SET OTK_manuf      = COALESCE((SELECT FLOOR(COALESCE(bp.`value_min`, 5) + RAND() * GREATEST(COALESCE(bp.`value_max`, 15) - COALESCE(bp.`value_min`, 5) + 1, 1)) FROM `bot_parameters` bp WHERE bp.`variable_name` = 'OTK_manuf' LIMIT 1), FLOOR(5 + RAND() * 11));
    SET OTK_assembly   = COALESCE((SELECT FLOOR(COALESCE(bp.`value_min`, 5) + RAND() * GREATEST(COALESCE(bp.`value_max`, 15) - COALESCE(bp.`value_min`, 5) + 1, 1)) FROM `bot_parameters` bp WHERE bp.`variable_name` = 'OTK_assembly' LIMIT 1), FLOOR(5 + RAND() * 11));
    SET OTK_shipped    = COALESCE((SELECT FLOOR(COALESCE(bp.`value_min`, 5) + RAND() * GREATEST(COALESCE(bp.`value_max`, 15) - COALESCE(bp.`value_min`, 5) + 1, 1)) FROM `bot_parameters` bp WHERE bp.`variable_name` = 'OTK_shipped' LIMIT 1), FLOOR(5 + RAND() * 11));
    SET OTK_loss       = COALESCE((SELECT FLOOR(COALESCE(bp.`value_min`, 5) + RAND() * GREATEST(COALESCE(bp.`value_max`, 15) - COALESCE(bp.`value_min`, 5) + 1, 1)) FROM `bot_parameters` bp WHERE bp.`variable_name` = 'OTK_loss' LIMIT 1), FLOOR(5 + RAND() * 11));

    SET sv_choice      = CASE WHEN COALESCE((SELECT FLOOR(COALESCE(bp.`value_min`, 0) + RAND() * GREATEST(COALESCE(bp.`value_max`, 3) - COALESCE(bp.`value_min`, 0) + 1, 1)) FROM `bot_parameters` bp WHERE bp.`variable_name` = 'sv_choice' LIMIT 1), FLOOR(0 + RAND() * 4)) = COALESCE((SELECT bp.`value_max` FROM `bot_parameters` bp WHERE bp.`variable_name` = 'sv_choice' LIMIT 1), 3) THEN 1 ELSE 0 END;
    SET sv_replace     = CASE WHEN COALESCE((SELECT FLOOR(COALESCE(bp.`value_min`, 0) + RAND() * GREATEST(COALESCE(bp.`value_max`, 5) - COALESCE(bp.`value_min`, 0) + 1, 1)) FROM `bot_parameters` bp WHERE bp.`variable_name` = 'sv_replace' LIMIT 1), FLOOR(0 + RAND() * 6)) = COALESCE((SELECT bp.`value_max` FROM `bot_parameters` bp WHERE bp.`variable_name` = 'sv_replace' LIMIT 1), 5) THEN 1 ELSE 0 END;

    SELECT m.`ERP_ID`
      INTO replace_to
    FROM `Main` m
    WHERE m.`ERP_ID` IS NOT NULL
      AND (
            v_projects IS NULL
         OR TRIM(COALESCE(v_projects, '')) = ''
         OR FIND_IN_SET(
              TRIM(COALESCE(CAST(m.`Project` AS CHAR CHARACTER SET utf8mb4), '')) COLLATE utf8mb4_unicode_ci,
              REPLACE(v_projects, ', ', ',') COLLATE utf8mb4_unicode_ci
            ) > 0
      )
    ORDER BY RAND()
    LIMIT 1;

    CALL bot_export_user(exp_row_count, exp_approve);
    CALL bot_purhaser(purch_purch, purch_byed, purch_manuf, prod_rework, purch_return, purch_cost);
    CALL bot_shopfloor(prod_kit, prod_assembled, prod_prod, prod_manuf, prod_purch, prod_shipped, prod_loss, prod_rework, prod_return);
    CALL bot_warehouse(wh_purch, wh_manuf, wh_return, wh_kit);
    CALL bot_OTK(OTK_manuf, OTK_assembly, OTK_shipped, OTK_loss);
    CALL bot_supervisor(sv_choice, sv_replace, replace_to);
END$$

DELIMITER ;
