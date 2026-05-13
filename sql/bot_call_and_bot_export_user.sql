-- Набор процедур bot_* для имитации действий пользователей.
-- bot_call читает диапазоны из bot_parameters и вызывает export/purchase/shopfloor/warehouse/OTK/supervisor.
-- Projects в bot_parameters ограничивает проекты, которые видят все bot_* процедуры.

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
            `Supplier`, `Contractor_INN`, `Contractor_KPP`, `Price_of_single_unit`, `Location`, `Source`, `Initial_doc_no`
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
            r.`Supplier`, r.`Contractor_INN`, r.`Contractor_KPP`, r.`Price_of_single_unit`, r.`Location`, r.`Source`, r.`Initial_doc_no`
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

    /* Оплачено + стоимость + случайный документ + случайный контрагент */
    IF COALESCE(purch_byed, 0) > 0 THEN
        UPDATE `Transactions` t
        INNER JOIN (
            SELECT
                picked.id,
                doc.`id` AS Document_id,
                doc.`Document_no`,
                doc.`Document_date`,
                contractor.`id` AS Contractor_id
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
            INNER JOIN `Contractors` contractor ON contractor.`id` = (
                SELECT c.`id`
                FROM `Contractors` c
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
            t.`Contractor_id` = r.`Contractor_id`,
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
              AND z.`Recommend_wh` = 'вернуть на склад'
              AND (z.`Order_prod` IS NULL OR z.`Order_prod` <> 'Вернуть на склад')
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
              AND z.`Recommend_wh` = 'вернуть на склад'
              AND z.`Order_prod` = 'Вернуть на склад'
              AND (z.`Order_wh` IS NULL OR z.`Order_wh` <> 'Принято на склад')
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
    DECLARE v_projects TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

    SELECT NULLIF(TRIM(MAX(CASE WHEN `variable_name` = 'Projects' THEN `text_parameter` END)), '')
      INTO v_projects
    FROM `bot_parameters`;

    IF COALESCE(sv_choice, 0) > 0 THEN
        UPDATE `Transactions` t
        INNER JOIN (
            SELECT z.`id`
            FROM `Transactions` z
            WHERE z.`Status_transaction` = 'В ожидании'
              AND (
                    z.`Status_warehouse` = 'Ожидает решения'
                 OR z.`Recommend_wh` IS NOT NULL
              )
              AND (z.`Order_sv` IS NULL OR TRIM(COALESCE(z.`Order_sv`, '')) = '')
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
        SET t.`Order_sv` = 'разбить',
            t.`updated_by` = CASE WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'supervisor' ELSE CONCAT(t.`updated_by`, '; ', 'supervisor') END,
            t.`updated_at` = CURRENT_TIMESTAMP;

        UPDATE `Transactions` t
        INNER JOIN (
            SELECT z.`id`
            FROM `Transactions` z
            WHERE z.`Status_transaction` = 'В ожидании'
              AND (
                    z.`Status_warehouse` = 'Ожидает решения'
                 OR z.`Recommend_wh` IS NOT NULL
              )
              AND (z.`Order_sv` IS NULL OR TRIM(COALESCE(z.`Order_sv`, '')) = '')
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
        SET t.`Order_sv` = 'забраковать',
            t.`updated_by` = CASE WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'supervisor' ELSE CONCAT(t.`updated_by`, '; ', 'supervisor') END,
            t.`updated_at` = CURRENT_TIMESTAMP;

        UPDATE `Transactions` t
        INNER JOIN (
            SELECT z.`id`
            FROM `Transactions` z
            WHERE z.`Status_transaction` = 'В ожидании'
              AND (
                    z.`Status_warehouse` = 'Ожидает решения'
                 OR z.`Recommend_wh` IS NOT NULL
              )
              AND (z.`Order_sv` IS NULL OR TRIM(COALESCE(z.`Order_sv`, '')) = '')
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
        SET t.`Order_sv` = 'отменить',
            t.`updated_by` = CASE WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'supervisor' ELSE CONCAT(t.`updated_by`, '; ', 'supervisor') END,
            t.`updated_at` = CURRENT_TIMESTAMP;

        UPDATE `Transactions` t
        INNER JOIN (
            SELECT z.`id`
            FROM `Transactions` z
            WHERE z.`Status_transaction` = 'В ожидании'
              AND (
                    z.`Status_warehouse` = 'Ожидает решения'
                 OR z.`Recommend_wh` IS NOT NULL
              )
              AND (z.`Order_sv` IS NULL OR TRIM(COALESCE(z.`Order_sv`, '')) = '')
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
        SET t.`Order_sv` = 'доработать запас',
            t.`updated_by` = CASE WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'supervisor' ELSE CONCAT(t.`updated_by`, '; ', 'supervisor') END,
            t.`updated_at` = CURRENT_TIMESTAMP;
    END IF;

    IF COALESCE(sv_replace, 0) > 0 THEN
        UPDATE `Transactions` t
        INNER JOIN (
            SELECT z.`id`
            FROM `Transactions` z
            WHERE z.`type` = 'move'
              AND z.`Status_transaction` = 'В ожидании'
              AND (
                    z.`Status_warehouse` = 'Ожидает решения'
                 OR z.`Recommend_wh` IS NOT NULL
              )
              AND z.`Recommend_wh` IS NOT NULL
              AND (z.`Order_sv` IS NULL OR TRIM(COALESCE(z.`Order_sv`, '')) = '')
              AND (z.`Replace_to` IS NULL OR TRIM(COALESCE(z.`Replace_to`, '')) = '')
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
        SET t.`Replace_to` = COALESCE(
                (
                    SELECT m.`ERP_ID`
                    FROM `Main` m
                    WHERE m.`ERP_ID` IS NOT NULL
                      AND TRIM(COALESCE(m.`ERP_ID`, '')) <> ''
                      AND m.`ERP_ID` COLLATE utf8mb4_unicode_ci <> t.`ERP_ID` COLLATE utf8mb4_unicode_ci
                    ORDER BY RAND()
                    LIMIT 1
                ),
                CASE
                    WHEN replace_to IS NOT NULL
                     AND TRIM(COALESCE(replace_to, '')) <> ''
                     AND replace_to COLLATE utf8mb4_unicode_ci <> t.`ERP_ID` COLLATE utf8mb4_unicode_ci
                    THEN replace_to
                    ELSE NULL
                END
            ),
            t.`Order_sv` = 'заменить со склада',
            t.`updated_by` = CASE WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'supervisor' ELSE CONCAT(t.`updated_by`, '; ', 'supervisor') END,
            t.`updated_at` = CURRENT_TIMESTAMP;

        UPDATE `Transactions` t
        INNER JOIN (
            SELECT z.`id`
            FROM `Transactions` z
            WHERE z.`Status_transaction` = 'В ожидании'
              AND (
                    z.`Status_warehouse` = 'Ожидает решения'
                 OR z.`Recommend_wh` IS NOT NULL
              )
              AND z.`Recommend_wh` IS NOT NULL
              AND (z.`Order_sv` IS NULL OR TRIM(COALESCE(z.`Order_sv`, '')) = '')
              AND (z.`Replace_to` IS NULL OR TRIM(COALESCE(z.`Replace_to`, '')) = '')
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
        SET t.`Replace_to` = COALESCE(
                (
                    SELECT m.`ERP_ID`
                    FROM `Main` m
                    WHERE m.`ERP_ID` IS NOT NULL
                      AND TRIM(COALESCE(m.`ERP_ID`, '')) <> ''
                      AND m.`ERP_ID` COLLATE utf8mb4_unicode_ci <> t.`ERP_ID` COLLATE utf8mb4_unicode_ci
                    ORDER BY RAND()
                    LIMIT 1
                ),
                CASE
                    WHEN replace_to IS NOT NULL
                     AND TRIM(COALESCE(replace_to, '')) <> ''
                     AND replace_to COLLATE utf8mb4_unicode_ci <> t.`ERP_ID` COLLATE utf8mb4_unicode_ci
                    THEN replace_to
                    ELSE NULL
                END
            ),
            t.`Order_sv` = 'заменить и восполнить',
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

    SELECT
        MAX(CASE WHEN bp.`variable_name` = 'exp_row_count'  THEN FLOOR(bp.`value_min` + RAND() * GREATEST(bp.`value_max` - bp.`value_min` + 1, 1)) END),
        MAX(CASE WHEN bp.`variable_name` = 'exp_approve'    THEN FLOOR(bp.`value_min` + RAND() * GREATEST(bp.`value_max` - bp.`value_min` + 1, 1)) END),
        MAX(CASE WHEN bp.`variable_name` = 'purch_purch'    THEN FLOOR(bp.`value_min` + RAND() * GREATEST(bp.`value_max` - bp.`value_min` + 1, 1)) END),
        MAX(CASE WHEN bp.`variable_name` = 'purch_byed'     THEN FLOOR(bp.`value_min` + RAND() * GREATEST(bp.`value_max` - bp.`value_min` + 1, 1)) END),
        MAX(CASE WHEN bp.`variable_name` = 'purch_manuf'    THEN FLOOR(bp.`value_min` + RAND() * GREATEST(bp.`value_max` - bp.`value_min` + 1, 1)) END),
        MAX(CASE WHEN bp.`variable_name` = 'prod_rework'    THEN FLOOR(bp.`value_min` + RAND() * GREATEST(bp.`value_max` - bp.`value_min` + 1, 1)) END),
        MAX(CASE WHEN bp.`variable_name` = 'purch_return'   THEN FLOOR(bp.`value_min` + RAND() * GREATEST(bp.`value_max` - bp.`value_min` + 1, 1)) END),
        MAX(CASE WHEN bp.`variable_name` = 'purch_cost'     THEN FLOOR(bp.`value_min` + RAND() * GREATEST(bp.`value_max` - bp.`value_min` + 1, 1)) END),
        MAX(CASE WHEN bp.`variable_name` = 'prod_kit'       THEN FLOOR(bp.`value_min` + RAND() * GREATEST(bp.`value_max` - bp.`value_min` + 1, 1)) END),
        MAX(CASE WHEN bp.`variable_name` = 'prod_assembled' THEN FLOOR(bp.`value_min` + RAND() * GREATEST(bp.`value_max` - bp.`value_min` + 1, 1)) END),
        MAX(CASE WHEN bp.`variable_name` = 'prod_prod'      THEN FLOOR(bp.`value_min` + RAND() * GREATEST(bp.`value_max` - bp.`value_min` + 1, 1)) END),
        MAX(CASE WHEN bp.`variable_name` = 'prod_manuf'     THEN FLOOR(bp.`value_min` + RAND() * GREATEST(bp.`value_max` - bp.`value_min` + 1, 1)) END),
        MAX(CASE WHEN bp.`variable_name` = 'prod_purch'     THEN FLOOR(bp.`value_min` + RAND() * GREATEST(bp.`value_max` - bp.`value_min` + 1, 1)) END),
        MAX(CASE WHEN bp.`variable_name` = 'prod_shipped'   THEN FLOOR(bp.`value_min` + RAND() * GREATEST(bp.`value_max` - bp.`value_min` + 1, 1)) END),
        MAX(CASE WHEN bp.`variable_name` = 'prod_loss'      THEN FLOOR(bp.`value_min` + RAND() * GREATEST(bp.`value_max` - bp.`value_min` + 1, 1)) END),
        MAX(CASE WHEN bp.`variable_name` = 'prod_return'    THEN FLOOR(bp.`value_min` + RAND() * GREATEST(bp.`value_max` - bp.`value_min` + 1, 1)) END),
        MAX(CASE WHEN bp.`variable_name` = 'wh_purch'       THEN FLOOR(bp.`value_min` + RAND() * GREATEST(bp.`value_max` - bp.`value_min` + 1, 1)) END),
        MAX(CASE WHEN bp.`variable_name` = 'wh_manuf'       THEN FLOOR(bp.`value_min` + RAND() * GREATEST(bp.`value_max` - bp.`value_min` + 1, 1)) END),
        MAX(CASE WHEN bp.`variable_name` = 'wh_return'      THEN FLOOR(bp.`value_min` + RAND() * GREATEST(bp.`value_max` - bp.`value_min` + 1, 1)) END),
        MAX(CASE WHEN bp.`variable_name` = 'wh_kit'         THEN FLOOR(bp.`value_min` + RAND() * GREATEST(bp.`value_max` - bp.`value_min` + 1, 1)) END),
        MAX(CASE WHEN bp.`variable_name` = 'OTK_manuf'      THEN FLOOR(bp.`value_min` + RAND() * GREATEST(bp.`value_max` - bp.`value_min` + 1, 1)) END),
        MAX(CASE WHEN bp.`variable_name` = 'OTK_assembly'   THEN FLOOR(bp.`value_min` + RAND() * GREATEST(bp.`value_max` - bp.`value_min` + 1, 1)) END),
        MAX(CASE WHEN bp.`variable_name` = 'OTK_shipped'    THEN FLOOR(bp.`value_min` + RAND() * GREATEST(bp.`value_max` - bp.`value_min` + 1, 1)) END),
        MAX(CASE WHEN bp.`variable_name` = 'OTK_loss'       THEN FLOOR(bp.`value_min` + RAND() * GREATEST(bp.`value_max` - bp.`value_min` + 1, 1)) END),
        MAX(CASE WHEN bp.`variable_name` = 'sv_choice'      THEN FLOOR(bp.`value_min` + RAND() * GREATEST(bp.`value_max` - bp.`value_min` + 1, 1)) END),
        MAX(CASE WHEN bp.`variable_name` = 'sv_replace'     THEN FLOOR(bp.`value_min` + RAND() * GREATEST(bp.`value_max` - bp.`value_min` + 1, 1)) END)
    INTO
        exp_row_count, exp_approve,
        purch_purch, purch_byed, purch_manuf, prod_rework, purch_return, purch_cost,
        prod_kit, prod_assembled, prod_prod, prod_manuf, prod_purch, prod_shipped, prod_loss, prod_return,
        wh_purch, wh_manuf, wh_return, wh_kit,
        OTK_manuf, OTK_assembly, OTK_shipped, OTK_loss,
        sv_choice, sv_replace
    FROM `bot_parameters` bp
    WHERE bp.`value_min` IS NOT NULL
      AND bp.`value_max` IS NOT NULL;

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
