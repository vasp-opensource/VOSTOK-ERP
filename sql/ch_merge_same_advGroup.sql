-- ch_merge_same_advGroup: объединение change «внешний → склад» по ERP_ID + Project + Advanced_group + Status_warehouse,
-- сумма Quantity_change; только Status_warehouse «В закупке» или «В изготовлении», Status_transaction «В ожидании».
-- Старые строки: Status_transaction «Заменено», Status_warehouse «Норма»; id суммарной строки дописывается в linked_transaction через "; ".
-- Новая строка: id суммарной дописывается в linked_transaction; шаблон полей — агрегаты по группе (MIN / SUM для Quantity_ordered).
-- Таблица Main не изменяется. Новые поля Transactions (Recommend_purchprod, Order_sv, Document_date, …) переносятся в суммарную строку.
-- Блокировка: lock_ch_merge_same_advGroup

DELIMITER $$

DROP PROCEDURE IF EXISTS ch_merge_same_advGroup$$

CREATE PROCEDURE ch_merge_same_advGroup()
BEGIN
    DECLARE v_lock_ok INT DEFAULT 0;
    DECLARE v_merge_left INT DEFAULT 0;
    DECLARE v_erp_id VARCHAR(255);
    DECLARE v_project_key TEXT;
    DECLARE v_ag_key TEXT;
    DECLARE v_wh VARCHAR(64);
    DECLARE v_new_id BIGINT UNSIGNED;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        IF v_lock_ok = 1 THEN
            DO RELEASE_LOCK('lock_ch_merge_same_advGroup');
        END IF;
        RESIGNAL;
    END;

    SELECT GET_LOCK('lock_ch_merge_same_advGroup', 0) INTO v_lock_ok;


    IF COALESCE(v_lock_ok, 0) <> 1 THEN

        SET @erp_batch_blocked_message = 'Blocked: lock_ch_merge_same_advGroup lock is already held';

    END IF;

    IF v_lock_ok = 1 THEN
        START TRANSACTION;

        DROP TEMPORARY TABLE IF EXISTS tmp_ch_merge_ids;
        CREATE TEMPORARY TABLE tmp_ch_merge_ids (
            `id` INT UNSIGNED PRIMARY KEY,
            `ERP_ID` VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
            `Project` TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
            `Advanced_group` TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
            `Status_warehouse` VARCHAR(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
            `Quantity_change` BIGINT NOT NULL
        );

        INSERT INTO tmp_ch_merge_ids (`id`, `ERP_ID`, `Project`, `Advanced_group`, `Status_warehouse`, `Quantity_change`)
        SELECT
            t.`id`,
            CAST(t.`ERP_ID` AS CHAR CHARACTER SET utf8mb4) COLLATE utf8mb4_unicode_ci,
            CAST(t.`Project` AS CHAR CHARACTER SET utf8mb4) COLLATE utf8mb4_unicode_ci,
            CAST(t.`Advanced_group` AS CHAR CHARACTER SET utf8mb4) COLLATE utf8mb4_unicode_ci,
            CAST(t.`Status_warehouse` AS CHAR CHARACTER SET utf8mb4) COLLATE utf8mb4_unicode_ci,
            COALESCE(t.`Quantity_change`, 0)
        FROM `Transactions` t
        WHERE t.`type` = 'change'
          AND t.`where_from` = 'внешний'
          AND t.`where_to` = 'склад'
          AND t.`Status_transaction` = 'В ожидании'
          AND t.`Status_warehouse` IN ('В закупке', 'В изготовлении')
          AND COALESCE(t.`Quantity_change`, 0) <> 0
          AND (t.`created_by` IS NULL OR t.`created_by` <> 'ch_merge_same_advGroup')
          AND EXISTS (
              SELECT 1
              FROM `Transactions` t2
              WHERE t2.`ERP_ID` COLLATE utf8mb4_unicode_ci = t.`ERP_ID` COLLATE utf8mb4_unicode_ci
                AND COALESCE(NULLIF(TRIM(t2.`Project` COLLATE utf8mb4_unicode_ci), '' COLLATE utf8mb4_unicode_ci), '' COLLATE utf8mb4_unicode_ci)
                    = COALESCE(NULLIF(TRIM(t.`Project` COLLATE utf8mb4_unicode_ci), '' COLLATE utf8mb4_unicode_ci), '' COLLATE utf8mb4_unicode_ci)
                AND COALESCE(NULLIF(TRIM(t2.`Advanced_group` COLLATE utf8mb4_unicode_ci), '' COLLATE utf8mb4_unicode_ci), '' COLLATE utf8mb4_unicode_ci)
                    = COALESCE(NULLIF(TRIM(t.`Advanced_group` COLLATE utf8mb4_unicode_ci), '' COLLATE utf8mb4_unicode_ci), '' COLLATE utf8mb4_unicode_ci)
                AND t2.`Status_warehouse` COLLATE utf8mb4_unicode_ci = t.`Status_warehouse` COLLATE utf8mb4_unicode_ci
                AND t2.`id` <> t.`id`
                AND t2.`type` = 'change'
                AND t2.`where_from` = 'внешний'
                AND t2.`where_to` = 'склад'
                AND t2.`Status_transaction` = 'В ожидании'
                AND t2.`Status_warehouse` IN ('В закупке', 'В изготовлении')
                AND COALESCE(t2.`Quantity_change`, 0) <> 0
                AND (t2.`created_by` IS NULL OR t2.`created_by` <> 'ch_merge_same_advGroup')
          );

        DROP TEMPORARY TABLE IF EXISTS tmp_ch_merge_agg;
        CREATE TEMPORARY TABLE tmp_ch_merge_agg AS
        SELECT
            x.`ERP_ID` COLLATE utf8mb4_unicode_ci AS `ERP_ID`,
            COALESCE(NULLIF(TRIM(x.`Project` COLLATE utf8mb4_unicode_ci), '' COLLATE utf8mb4_unicode_ci), '' COLLATE utf8mb4_unicode_ci) AS `project_key`,
            COALESCE(NULLIF(TRIM(x.`Advanced_group` COLLATE utf8mb4_unicode_ci), '' COLLATE utf8mb4_unicode_ci), '' COLLATE utf8mb4_unicode_ci) AS `ag_key`,
            x.`Status_warehouse` COLLATE utf8mb4_unicode_ci AS `Status_warehouse`,
            COUNT(*) AS `cnt`,
            SUM(COALESCE(t.`Quantity_change`, 0)) AS `sum_qty`
        FROM tmp_ch_merge_ids x
        INNER JOIN `Transactions` t ON t.`id` = x.`id`
        GROUP BY x.`ERP_ID` COLLATE utf8mb4_unicode_ci,
                 COALESCE(NULLIF(TRIM(x.`Project` COLLATE utf8mb4_unicode_ci), '' COLLATE utf8mb4_unicode_ci), '' COLLATE utf8mb4_unicode_ci),
                 COALESCE(NULLIF(TRIM(x.`Advanced_group` COLLATE utf8mb4_unicode_ci), '' COLLATE utf8mb4_unicode_ci), '' COLLATE utf8mb4_unicode_ci),
                 x.`Status_warehouse` COLLATE utf8mb4_unicode_ci
        HAVING `cnt` >= 2;

        DROP TEMPORARY TABLE IF EXISTS tmp_ch_merge_replace_queue;
        CREATE TEMPORARY TABLE tmp_ch_merge_replace_queue (
            `id` INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
            `ERP_ID` VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
            `project_key` TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
            `ag_key` TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
            `Status_warehouse` VARCHAR(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL
        );

        INSERT INTO tmp_ch_merge_replace_queue (`ERP_ID`, `project_key`, `ag_key`, `Status_warehouse`)
        SELECT `ERP_ID`, `project_key`, `ag_key`, `Status_warehouse` FROM tmp_ch_merge_agg;

        replace_loop: LOOP
            SELECT COUNT(*) INTO v_merge_left FROM tmp_ch_merge_replace_queue;
            IF v_merge_left = 0 THEN
                LEAVE replace_loop;
            END IF;

            SELECT `ERP_ID`, `project_key`, `ag_key`, `Status_warehouse`
              INTO v_erp_id, v_project_key, v_ag_key, v_wh
            FROM tmp_ch_merge_replace_queue
            ORDER BY `id`
            LIMIT 1;

            INSERT INTO `Transactions` (
                ERP_ID, linked_transaction, type, where_from, where_to,
                Quantity_of_parts_total, Quantity_change, Status_transaction,
                Project, Target_assembly, Supplied_component_number, Component_revision, Component_name,
                Quantity_in_target_assembly, Quantity_of_target_assemblies, Components_quantity_in_assembly,
                Assembly_batch_id, Assembly_batch_name, Assembly_batch_status, Assembly_batch_priority,
                Component_type, For_supplied_as_assembly_components_provided_by_supplier, Part_material,
                Producer, Catalogue_number, Producer_article, Distributer, Distributer_article,
                MBOM_type, Mass_kg, Unit_of_measure, Height, Width, Length,
                Advanced_group, Address,
                Recommend_purchprod,
                Order_purch, Order_wh, Order_prod, Order_OTK,
                Order_sv, Recommend_wh, Quantity_ordered, Replace_to, Rework_to, Rework_from,
                Status_warehouse,
                Document_no, Document_date, Zakaz_no, Date_needed, Date_expected, Cost_total_rub,
                Supplier, Location, Source, Initial_doc_no,
                created_by, updated_by, created_at, updated_at
            )
            SELECT
                g.`ERP_ID`,
                NULL,
                'change',
                'внешний',
                'склад',
                0,
                g.`sum_qty`,
                CASE WHEN g.`sum_qty` <= 0 THEN 'Отменено' ELSE 'В ожидании' END,
                fld.`Project`, fld.`Target_assembly`, fld.`Supplied_component_number`, fld.`Component_revision`, fld.`Component_name`,
                fld.`Quantity_in_target_assembly`, fld.`Quantity_of_target_assemblies`, fld.`Components_quantity_in_assembly`,
                fld.`Assembly_batch_id`, fld.`Assembly_batch_name`, fld.`Assembly_batch_status`, fld.`Assembly_batch_priority`,
                fld.`Component_type`, fld.`For_supplied_as_assembly_components_provided_by_supplier`, fld.`Part_material`,
                fld.`Producer`, fld.`Catalogue_number`, fld.`Producer_article`, fld.`Distributer`, fld.`Distributer_article`,
                fld.`MBOM_type`, fld.`Mass_kg`, fld.`Unit_of_measure`, fld.`Height`, fld.`Width`, fld.`Length`,
                fld.`Advanced_group`, fld.`Address`,
                fld.`Recommend_purchprod`,
                fld.`Order_purch`,
                NULL,
                fld.`Order_prod`,
                fld.`Order_OTK`,
                fld.`Order_sv`,
                fld.`Recommend_wh`,
                fld.`sum_qty_ord`,
                fld.`Replace_to`,
                fld.`Rework_to`,
                fld.`Rework_from`,
                CASE WHEN g.`sum_qty` <= 0 THEN 'Норма' ELSE g.`Status_warehouse` END,
                fld.`Document_no`,
                fld.`Document_date`,
                fld.`Zakaz_no`, fld.`Date_needed`, fld.`Date_expected`, fld.`Cost_total_rub`,
                fld.`Supplier`, fld.`Location`, fld.`Source`, fld.`Initial_doc_no`,
                'ch_merge_same_advGroup',
                'ch_merge_same_advGroup',
                NOW(),
                NOW()
            FROM tmp_ch_merge_agg g
            INNER JOIN (
                SELECT
                    q.`ERP_ID`,
                    q.`project_key`,
                    q.`ag_key`,
                    q.`Status_warehouse`,
                    MIN(q.`Project`) AS `Project`,
                    MIN(q.`Target_assembly`) AS `Target_assembly`,
                    MIN(q.`Supplied_component_number`) AS `Supplied_component_number`,
                    MIN(q.`Component_revision`) AS `Component_revision`,
                    MIN(q.`Component_name`) AS `Component_name`,
                    MIN(q.`Quantity_in_target_assembly`) AS `Quantity_in_target_assembly`,
                    MIN(q.`Quantity_of_target_assemblies`) AS `Quantity_of_target_assemblies`,
                    MIN(q.`Components_quantity_in_assembly`) AS `Components_quantity_in_assembly`,
                    MIN(q.`Assembly_batch_id`) AS `Assembly_batch_id`,
                    MIN(q.`Assembly_batch_name`) AS `Assembly_batch_name`,
                    MIN(q.`Assembly_batch_status`) AS `Assembly_batch_status`,
                    MIN(q.`Assembly_batch_priority`) AS `Assembly_batch_priority`,
                    MIN(q.`Component_type`) AS `Component_type`,
                    MIN(q.`For_supplied_as_assembly_components_provided_by_supplier`) AS `For_supplied_as_assembly_components_provided_by_supplier`,
                    MIN(q.`Part_material`) AS `Part_material`,
                    MIN(q.`Producer`) AS `Producer`,
                    MIN(q.`Catalogue_number`) AS `Catalogue_number`,
                    MIN(q.`Producer_article`) AS `Producer_article`,
                    MIN(q.`Distributer`) AS `Distributer`,
                    MIN(q.`Distributer_article`) AS `Distributer_article`,
                    MIN(q.`MBOM_type`) AS `MBOM_type`,
                    MIN(q.`Mass_kg`) AS `Mass_kg`,
                    MIN(q.`Unit_of_measure`) AS `Unit_of_measure`,
                    MIN(q.`Height`) AS `Height`,
                    MIN(q.`Width`) AS `Width`,
                    MIN(q.`Length`) AS `Length`,
                    MIN(q.`Advanced_group`) AS `Advanced_group`,
                    MIN(q.`Address`) AS `Address`,
                    MIN(q.`Recommend_purchprod`) AS `Recommend_purchprod`,
                    MIN(q.`Document_no`) AS `Document_no`,
                    MIN(q.`Document_date`) AS `Document_date`,
                    MIN(q.`Zakaz_no`) AS `Zakaz_no`,
                    MIN(q.`Date_needed`) AS `Date_needed`,
                    MIN(q.`Date_expected`) AS `Date_expected`,
                    MIN(q.`Cost_total_rub`) AS `Cost_total_rub`,
                    MIN(q.`Supplier`) AS `Supplier`,
                    MIN(q.`Location`) AS `Location`,
                    MIN(q.`Source`) AS `Source`,
                    MIN(q.`Initial_doc_no`) AS `Initial_doc_no`,
                    MIN(q.`Order_purch`) AS `Order_purch`,
                    MIN(q.`Order_prod`) AS `Order_prod`,
                    MIN(q.`Order_OTK`) AS `Order_OTK`,
                    MIN(q.`Order_sv`) AS `Order_sv`,
                    MIN(q.`Recommend_wh`) AS `Recommend_wh`,
                    SUM(COALESCE(q.`Quantity_ordered`, 0)) AS `sum_qty_ord`,
                    MIN(q.`Replace_to`) AS `Replace_to`,
                    MIN(q.`Rework_to`) AS `Rework_to`,
                    MIN(q.`Rework_from`) AS `Rework_from`
                FROM (
                    SELECT
                        CAST(t.`ERP_ID` AS CHAR CHARACTER SET utf8mb4) COLLATE utf8mb4_unicode_ci AS `ERP_ID`,
                        COALESCE(NULLIF(TRIM(t.`Project` COLLATE utf8mb4_unicode_ci), '' COLLATE utf8mb4_unicode_ci), '' COLLATE utf8mb4_unicode_ci) AS `project_key`,
                        COALESCE(NULLIF(TRIM(t.`Advanced_group` COLLATE utf8mb4_unicode_ci), '' COLLATE utf8mb4_unicode_ci), '' COLLATE utf8mb4_unicode_ci) AS `ag_key`,
                        CAST(t.`Status_warehouse` AS CHAR CHARACTER SET utf8mb4) COLLATE utf8mb4_unicode_ci AS `Status_warehouse`,
                        t.`Project`, t.`Target_assembly`, t.`Supplied_component_number`, t.`Component_revision`, t.`Component_name`,
                        t.`Quantity_in_target_assembly`, t.`Quantity_of_target_assemblies`, t.`Components_quantity_in_assembly`,
                        t.`Assembly_batch_id`, t.`Assembly_batch_name`, t.`Assembly_batch_status`, t.`Assembly_batch_priority`,
                        t.`Component_type`, t.`For_supplied_as_assembly_components_provided_by_supplier`, t.`Part_material`,
                        t.`Producer`, t.`Catalogue_number`, t.`Producer_article`, t.`Distributer`, t.`Distributer_article`,
                        t.`MBOM_type`, t.`Mass_kg`, t.`Unit_of_measure`, t.`Height`, t.`Width`, t.`Length`,
                        t.`Advanced_group`, t.`Address`, t.`Recommend_purchprod`, t.`Document_no`, t.`Document_date`,
                        t.`Zakaz_no`, t.`Date_needed`, t.`Date_expected`, t.`Cost_total_rub`, t.`Supplier`, t.`Location`,
                        t.`Source`, t.`Initial_doc_no`, t.`Order_purch`, t.`Order_prod`, t.`Order_OTK`, t.`Order_sv`,
                        t.`Recommend_wh`, t.`Quantity_ordered`, t.`Replace_to`, t.`Rework_to`, t.`Rework_from`
                    FROM `Transactions` t
                    INNER JOIN tmp_ch_merge_ids x ON x.`id` = t.`id`
                ) q
                GROUP BY q.`ERP_ID`, q.`project_key`, q.`ag_key`, q.`Status_warehouse`
            ) fld
              ON fld.`ERP_ID` COLLATE utf8mb4_unicode_ci = g.`ERP_ID` COLLATE utf8mb4_unicode_ci
             AND fld.`project_key` COLLATE utf8mb4_unicode_ci = g.`project_key` COLLATE utf8mb4_unicode_ci
             AND fld.`ag_key` COLLATE utf8mb4_unicode_ci = g.`ag_key` COLLATE utf8mb4_unicode_ci
             AND fld.`Status_warehouse` COLLATE utf8mb4_unicode_ci = g.`Status_warehouse` COLLATE utf8mb4_unicode_ci
            WHERE g.`cnt` >= 2
              AND g.`ERP_ID` COLLATE utf8mb4_unicode_ci = v_erp_id COLLATE utf8mb4_unicode_ci
              AND g.`project_key` COLLATE utf8mb4_unicode_ci = v_project_key COLLATE utf8mb4_unicode_ci
              AND g.`ag_key` COLLATE utf8mb4_unicode_ci = v_ag_key COLLATE utf8mb4_unicode_ci
              AND g.`Status_warehouse` COLLATE utf8mb4_unicode_ci = v_wh COLLATE utf8mb4_unicode_ci;

            SET v_new_id = LAST_INSERT_ID();

            UPDATE `Transactions` t
            SET
                t.`linked_transaction` = CASE
                    WHEN t.`linked_transaction` IS NULL OR TRIM(COALESCE(t.`linked_transaction`, '')) = '' THEN CAST(v_new_id AS CHAR)
                    ELSE CONCAT(TRIM(t.`linked_transaction`), '; ', v_new_id)
                END,
                t.`updated_at`         = NOW(),
                t.`updated_by`         = CASE
                                            WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'ch_merge_same_advGroup'
                                            ELSE CONCAT(t.`updated_by`, '; ', 'ch_merge_same_advGroup')
                                         END
            WHERE t.`id` = v_new_id;

            UPDATE `Transactions` t
            INNER JOIN tmp_ch_merge_ids x ON x.`id` = t.`id`
            INNER JOIN tmp_ch_merge_agg g
              ON g.`ERP_ID` COLLATE utf8mb4_unicode_ci = x.`ERP_ID` COLLATE utf8mb4_unicode_ci
             AND g.`project_key` COLLATE utf8mb4_unicode_ci = COALESCE(NULLIF(TRIM(x.`Project` COLLATE utf8mb4_unicode_ci), '' COLLATE utf8mb4_unicode_ci), '' COLLATE utf8mb4_unicode_ci)
             AND g.`ag_key` COLLATE utf8mb4_unicode_ci = COALESCE(NULLIF(TRIM(x.`Advanced_group` COLLATE utf8mb4_unicode_ci), '' COLLATE utf8mb4_unicode_ci), '' COLLATE utf8mb4_unicode_ci)
             AND g.`Status_warehouse` COLLATE utf8mb4_unicode_ci = x.`Status_warehouse` COLLATE utf8mb4_unicode_ci
            SET
                t.`linked_transaction` = CASE
                    WHEN t.`linked_transaction` IS NULL OR TRIM(COALESCE(t.`linked_transaction`, '')) = '' THEN CAST(v_new_id AS CHAR)
                    ELSE CONCAT(TRIM(t.`linked_transaction`), '; ', v_new_id)
                END,
                t.`Status_transaction` = 'Заменено',
                t.`Status_warehouse`   = 'Норма',
                t.`updated_at`         = NOW(),
                t.`updated_by`         = CASE
                                            WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'ch_merge_same_advGroup'
                                            ELSE CONCAT(t.`updated_by`, '; ', 'ch_merge_same_advGroup')
                                         END
            WHERE g.`cnt` >= 2
              AND g.`ERP_ID` COLLATE utf8mb4_unicode_ci = v_erp_id COLLATE utf8mb4_unicode_ci
              AND g.`project_key` COLLATE utf8mb4_unicode_ci = v_project_key COLLATE utf8mb4_unicode_ci
              AND g.`ag_key` COLLATE utf8mb4_unicode_ci = v_ag_key COLLATE utf8mb4_unicode_ci
              AND g.`Status_warehouse` COLLATE utf8mb4_unicode_ci = v_wh COLLATE utf8mb4_unicode_ci;

            DELETE FROM tmp_ch_merge_replace_queue
            WHERE `ERP_ID` COLLATE utf8mb4_unicode_ci = v_erp_id COLLATE utf8mb4_unicode_ci
              AND `project_key` COLLATE utf8mb4_unicode_ci <=> v_project_key COLLATE utf8mb4_unicode_ci
              AND `ag_key` COLLATE utf8mb4_unicode_ci <=> v_ag_key COLLATE utf8mb4_unicode_ci
              AND `Status_warehouse` COLLATE utf8mb4_unicode_ci = v_wh COLLATE utf8mb4_unicode_ci;
        END LOOP replace_loop;

        DROP TEMPORARY TABLE IF EXISTS tmp_ch_merge_replace_queue;
        DROP TEMPORARY TABLE IF EXISTS tmp_ch_merge_agg;
        DROP TEMPORARY TABLE IF EXISTS tmp_ch_merge_ids;

        COMMIT;
        DO RELEASE_LOCK('lock_ch_merge_same_advGroup');
    END IF;
END$$

DELIMITER ;
