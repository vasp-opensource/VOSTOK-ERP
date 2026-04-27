-- ch_merge_same_advGroup: объединение change «внешний → склад» по ERP_ID + Advanced_group + Status_warehouse,
-- сумма Quantity_change; только Status_warehouse «В закупке» или «В изготовлении», Status_transaction «В ожидании».
-- Старые строки: Status_transaction «Заменено», Status_warehouse «Норма», linked_transaction → суммарная строка.
-- Новая строка: linked_transaction = собственный id; шаблон полей — строка с MIN(id) в группе.
-- Блокировка: lock_ch_merge_same_advGroup

DELIMITER $$

DROP PROCEDURE IF EXISTS ch_merge_same_advGroup$$

CREATE PROCEDURE ch_merge_same_advGroup()
BEGIN
    DECLARE v_lock_ok INT DEFAULT 0;
    DECLARE v_merge_left INT DEFAULT 0;
    DECLARE v_erp_id VARCHAR(255);
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

    IF v_lock_ok = 1 THEN
        START TRANSACTION;

        DROP TEMPORARY TABLE IF EXISTS tmp_ch_merge_ids;
        CREATE TEMPORARY TABLE tmp_ch_merge_ids (
            `id` INT UNSIGNED PRIMARY KEY,
            `ERP_ID` VARCHAR(255) NOT NULL,
            `Advanced_group` TEXT NULL,
            `Status_warehouse` VARCHAR(64) NOT NULL,
            `Quantity_change` BIGINT NOT NULL
        );

        INSERT INTO tmp_ch_merge_ids (`id`, `ERP_ID`, `Advanced_group`, `Status_warehouse`, `Quantity_change`)
        SELECT
            t.`id`,
            t.`ERP_ID`,
            t.`Advanced_group`,
            t.`Status_warehouse`,
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
              WHERE t2.`ERP_ID` = t.`ERP_ID`
                AND COALESCE(NULLIF(TRIM(t2.`Advanced_group`), ''), '')
                    = COALESCE(NULLIF(TRIM(t.`Advanced_group`), ''), '')
                AND t2.`Status_warehouse` = t.`Status_warehouse`
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
            x.`ERP_ID` AS `ERP_ID`,
            COALESCE(NULLIF(TRIM(x.`Advanced_group`), ''), '') AS `ag_key`,
            x.`Status_warehouse` AS `Status_warehouse`,
            COUNT(*) AS `cnt`,
            SUM(COALESCE(t.`Quantity_change`, 0)) AS `sum_qty`
        FROM tmp_ch_merge_ids x
        INNER JOIN `Transactions` t ON t.`id` = x.`id`
        GROUP BY x.`ERP_ID`, COALESCE(NULLIF(TRIM(x.`Advanced_group`), ''), ''), x.`Status_warehouse`
        HAVING `cnt` >= 2;

        DROP TEMPORARY TABLE IF EXISTS tmp_ch_merge_replace_queue;
        CREATE TEMPORARY TABLE tmp_ch_merge_replace_queue (
            `id` INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
            `ERP_ID` VARCHAR(255) NOT NULL,
            `ag_key` TEXT NOT NULL,
            `Status_warehouse` VARCHAR(64) NOT NULL
        );

        INSERT INTO tmp_ch_merge_replace_queue (`ERP_ID`, `ag_key`, `Status_warehouse`)
        SELECT `ERP_ID`, `ag_key`, `Status_warehouse` FROM tmp_ch_merge_agg;

        replace_loop: LOOP
            SELECT COUNT(*) INTO v_merge_left FROM tmp_ch_merge_replace_queue;
            IF v_merge_left = 0 THEN
                LEAVE replace_loop;
            END IF;

            SELECT `ERP_ID`, `ag_key`, `Status_warehouse`
              INTO v_erp_id, v_ag_key, v_wh
            FROM tmp_ch_merge_replace_queue
            ORDER BY `id`
            LIMIT 1;

            INSERT INTO `Transactions` (
                ERP_ID, linked_transaction, type, where_from, where_to,
                Quantity_of_parts_total, Quantity_change, Status_transaction,
                Project, Target_assembly, Supplied_component_number, Component_revision, Component_name,
                Quantity_in_target_assembly, Quantity_of_target_assemblies, Components_quantity_in_assembly,
                Component_type, For_supplied_as_assembly_components_provided_by_supplier, Part_material,
                Producer, Catalogue_number, Producer_article, Distributer, Distributer_article,
                MBOM_type, Mass_kg, Unit_of_measure, Height, Width, Length,
                Advanced_group, Address,
                Document_no, Zakaz_no, Date_needed, Date_expected, Cost_total_rub,
                Supplier, Location, Source, Initial_doc_no,
                Order_purch, Order_wh, Order_prod, Order_OTK, Status_warehouse,
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
                fld.`Component_type`, fld.`For_supplied_as_assembly_components_provided_by_supplier`, fld.`Part_material`,
                fld.`Producer`, fld.`Catalogue_number`, fld.`Producer_article`, fld.`Distributer`, fld.`Distributer_article`,
                fld.`MBOM_type`, fld.`Mass_kg`, fld.`Unit_of_measure`, fld.`Height`, fld.`Width`, fld.`Length`,
                fld.`Advanced_group`, fld.`Address`,
                fld.`Document_no`, fld.`Zakaz_no`, fld.`Date_needed`, fld.`Date_expected`, fld.`Cost_total_rub`,
                fld.`Supplier`, fld.`Location`, fld.`Source`, fld.`Initial_doc_no`,
                fld.`Order_purch`,
                NULL,
                fld.`Order_prod`,
                fld.`Order_OTK`,
                CASE WHEN g.`sum_qty` <= 0 THEN 'Норма' ELSE g.`Status_warehouse` END,
                'ch_merge_same_advGroup',
                'ch_merge_same_advGroup',
                NOW(),
                NOW()
            FROM tmp_ch_merge_agg g
            INNER JOIN (
                SELECT
                    t.`ERP_ID`,
                    COALESCE(NULLIF(TRIM(t.`Advanced_group`), ''), '') AS `ag_key`,
                    t.`Status_warehouse` AS `Status_warehouse`,
                    MIN(t.`Project`) AS `Project`,
                    MIN(t.`Target_assembly`) AS `Target_assembly`,
                    MIN(t.`Supplied_component_number`) AS `Supplied_component_number`,
                    MIN(t.`Component_revision`) AS `Component_revision`,
                    MIN(t.`Component_name`) AS `Component_name`,
                    MIN(t.`Quantity_in_target_assembly`) AS `Quantity_in_target_assembly`,
                    MIN(t.`Quantity_of_target_assemblies`) AS `Quantity_of_target_assemblies`,
                    MIN(t.`Components_quantity_in_assembly`) AS `Components_quantity_in_assembly`,
                    MIN(t.`Component_type`) AS `Component_type`,
                    MIN(t.`For_supplied_as_assembly_components_provided_by_supplier`) AS `For_supplied_as_assembly_components_provided_by_supplier`,
                    MIN(t.`Part_material`) AS `Part_material`,
                    MIN(t.`Producer`) AS `Producer`,
                    MIN(t.`Catalogue_number`) AS `Catalogue_number`,
                    MIN(t.`Producer_article`) AS `Producer_article`,
                    MIN(t.`Distributer`) AS `Distributer`,
                    MIN(t.`Distributer_article`) AS `Distributer_article`,
                    MIN(t.`MBOM_type`) AS `MBOM_type`,
                    MIN(t.`Mass_kg`) AS `Mass_kg`,
                    MIN(t.`Unit_of_measure`) AS `Unit_of_measure`,
                    MIN(t.`Height`) AS `Height`,
                    MIN(t.`Width`) AS `Width`,
                    MIN(t.`Length`) AS `Length`,
                    MIN(t.`Advanced_group`) AS `Advanced_group`,
                    MIN(t.`Address`) AS `Address`,
                    MIN(t.`Document_no`) AS `Document_no`,
                    MIN(t.`Zakaz_no`) AS `Zakaz_no`,
                    MIN(t.`Date_needed`) AS `Date_needed`,
                    MIN(t.`Date_expected`) AS `Date_expected`,
                    MIN(t.`Cost_total_rub`) AS `Cost_total_rub`,
                    MIN(t.`Supplier`) AS `Supplier`,
                    MIN(t.`Location`) AS `Location`,
                    MIN(t.`Source`) AS `Source`,
                    MIN(t.`Initial_doc_no`) AS `Initial_doc_no`,
                    MIN(t.`Order_purch`) AS `Order_purch`,
                    MIN(t.`Order_prod`) AS `Order_prod`,
                    MIN(t.`Order_OTK`) AS `Order_OTK`
                FROM `Transactions` t
                INNER JOIN tmp_ch_merge_ids x ON x.`id` = t.`id`
                GROUP BY t.`ERP_ID`, COALESCE(NULLIF(TRIM(t.`Advanced_group`), ''), ''), t.`Status_warehouse`
            ) fld
              ON fld.`ERP_ID` = g.`ERP_ID`
             AND fld.`ag_key` = g.`ag_key`
             AND fld.`Status_warehouse` = g.`Status_warehouse`
            WHERE g.`cnt` >= 2
              AND g.`ERP_ID` = v_erp_id
              AND g.`ag_key` = v_ag_key
              AND g.`Status_warehouse` = v_wh;

            SET v_new_id = LAST_INSERT_ID();

            UPDATE `Transactions` t
            SET
                t.`linked_transaction` = v_new_id,
                t.`updated_at`         = NOW(),
                t.`updated_by`         = CASE
                                            WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'ch_merge_same_advGroup'
                                            ELSE CONCAT(t.`updated_by`, '; ', 'ch_merge_same_advGroup')
                                         END
            WHERE t.`id` = v_new_id;

            UPDATE `Transactions` t
            INNER JOIN tmp_ch_merge_ids x ON x.`id` = t.`id`
            INNER JOIN tmp_ch_merge_agg g
              ON g.`ERP_ID` = x.`ERP_ID`
             AND g.`ag_key` = COALESCE(NULLIF(TRIM(x.`Advanced_group`), ''), '')
             AND g.`Status_warehouse` = x.`Status_warehouse`
            SET
                t.`linked_transaction` = v_new_id,
                t.`Status_transaction` = 'Заменено',
                t.`Status_warehouse`   = 'Норма',
                t.`updated_at`         = NOW(),
                t.`updated_by`         = CASE
                                            WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'ch_merge_same_advGroup'
                                            ELSE CONCAT(t.`updated_by`, '; ', 'ch_merge_same_advGroup')
                                         END
            WHERE g.`cnt` >= 2
              AND g.`ERP_ID` = v_erp_id
              AND g.`ag_key` = v_ag_key
              AND g.`Status_warehouse` = v_wh;

            DELETE FROM tmp_ch_merge_replace_queue
            WHERE `ERP_ID` = v_erp_id
              AND `ag_key` <=> v_ag_key
              AND `Status_warehouse` = v_wh;
        END LOOP replace_loop;

        DROP TEMPORARY TABLE IF EXISTS tmp_ch_merge_replace_queue;
        DROP TEMPORARY TABLE IF EXISTS tmp_ch_merge_agg;
        DROP TEMPORARY TABLE IF EXISTS tmp_ch_merge_ids;

        COMMIT;
        DO RELEASE_LOCK('lock_ch_merge_same_advGroup');
    END IF;
END$$

DELIMITER ;
