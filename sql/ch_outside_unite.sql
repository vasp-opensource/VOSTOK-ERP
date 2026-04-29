-- ch_outside_unite: общая логика неттинга change (внешний→склад), Main, merge по группам ERP_ID + Advanced_group.
-- Перед любыми изменениями Transactions по tmp_ch_outside_unite_ids: recommend_change_unite_clear (recommend_change_unite_clear.sql)
-- сбрасывает Recommend_purchprod.
-- Вызывается после заполнения tmp_ch_outside_unite_ids (входящие + партнёры) в ch_outside_to_purch / ch_outside_to_ownProd.
-- Параметры: блокировка, Source, метка процедуры (created_by/updated_by, исключение merge-строк из партнёров — в отборе у вызывающего),
-- статусы склада для массового UPDATE, суммарной вставки и одиночной строки, режим поля Main (закупка / изготовление).

DELIMITER $$

DROP PROCEDURE IF EXISTS ch_outside_unite$$

CREATE PROCEDURE ch_outside_unite(
    IN p_lock_name VARCHAR(64),
    IN p_source VARCHAR(64),
    IN p_proc_name VARCHAR(64),
    IN p_wh_bulk VARCHAR(64),
    IN p_wh_merge VARCHAR(64),
    IN p_wh_single VARCHAR(64),
    IN p_main_use_manufacturing TINYINT(1)
)
BEGIN
    DECLARE v_lock_ok INT DEFAULT 0;
    DECLARE v_erp_id VARCHAR(255);
    DECLARE v_erp_row_id INT UNSIGNED DEFAULT 0;
    DECLARE v_ag_key TEXT;
    DECLARE v_pos_ag_key TEXT;
    DECLARE v_neg_ag_key TEXT;
    DECLARE v_pos_qty BIGINT DEFAULT 0;
    DECLARE v_neg_left BIGINT DEFAULT 0;
    DECLARE v_take BIGINT DEFAULT 0;
    DECLARE v_new_id INT UNSIGNED;
    DECLARE v_queue_left INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        IF v_lock_ok = 1 THEN
            DO RELEASE_LOCK(@ch_outside_unite_lock);
        END IF;
        RESIGNAL;
    END;

    SET @ch_outside_unite_lock = p_lock_name;

    SELECT GET_LOCK(p_lock_name, 0) INTO v_lock_ok;

    IF v_lock_ok = 1 THEN
        START TRANSACTION;

        /* 2) Склад и Source: в «закупке/изготовлении» только неотрицательные qty.
           Отрицательный change не должен попадать в контур приёмки (ch_*_to_wh) до неттинга:
           остаётся «Новая», затем после зачёта — Отменено/Норма или сводная строка. */
        UPDATE `Transactions` t
        INNER JOIN tmp_ch_outside_unite_ids x ON x.id = t.id
        SET
            t.`Status_warehouse` = CASE
                                      WHEN COALESCE(t.`Quantity_change`, 0) < 0 THEN 'Новая'
                                      ELSE p_wh_bulk
                                   END,
            t.`Source`           = p_source,
            t.`updated_at`       = NOW(),
            t.`updated_by`       = CASE
                                      WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN p_proc_name
                                      ELSE CONCAT(t.`updated_by`, '; ', p_proc_name)
                                   END;

        /* Защита от ложного неттинга в одном такте:
           если по ERP_ID есть входящий отрицательный change и одновременно есть
           строка, готовая к приемке на склад (Оплачено + Принято на склад + Cost_total_rub > 0),
           такой ERP_ID откладываем на следующий такт. */
        DROP TEMPORARY TABLE IF EXISTS tmp_ch_outside_unite_defer_erp;
        CREATE TEMPORARY TABLE tmp_ch_outside_unite_defer_erp AS
        SELECT DISTINCT i.`ERP_ID`
        FROM tmp_ch_outside_unite_ids i
        INNER JOIN `Transactions` ti ON ti.`id` = i.`id`
        INNER JOIN `Transactions` tp
          ON tp.`ERP_ID` = i.`ERP_ID`
        WHERE i.`is_incoming` = 1
          AND COALESCE(ti.`Quantity_change`, 0) < 0
          AND tp.`type` = 'change'
          AND tp.`where_from` = 'внешний'
          AND tp.`where_to` = 'склад'
          AND tp.`Status_transaction` = 'В ожидании'
          AND tp.`Status_warehouse` = 'В закупке'
          AND tp.`Order_purch` = 'Оплачено'
          AND tp.`Order_wh` = 'Принято на склад'
          AND COALESCE(tp.`Cost_total_rub`, 0) > 0;

        DELETE x
        FROM tmp_ch_outside_unite_ids x
        INNER JOIN tmp_ch_outside_unite_defer_erp d ON d.`ERP_ID` = x.`ERP_ID`;

        DROP TEMPORARY TABLE IF EXISTS tmp_ch_outside_unite_defer_erp;

        /* 3) Агрегаты по группам */
        DROP TEMPORARY TABLE IF EXISTS tmp_ch_outside_unite_group_agg;
        CREATE TEMPORARY TABLE tmp_ch_outside_unite_group_agg AS
        SELECT
            x.`ERP_ID` AS ERP_ID,
            COALESCE(NULLIF(TRIM(x.`Advanced_group`), ''), '') AS ag_key,
            COUNT(*) AS cnt,
            SUM(x.`Quantity_change`) AS sum_qty,
            SUM(CASE WHEN x.`is_incoming` = 1 THEN x.`Quantity_change` ELSE 0 END) AS sum_incoming
        FROM tmp_ch_outside_unite_ids x
        GROUP BY x.`ERP_ID`, COALESCE(NULLIF(TRIM(x.`Advanced_group`), ''), '');

        ALTER TABLE tmp_ch_outside_unite_group_agg
            ADD COLUMN adj_qty BIGINT NOT NULL DEFAULT 0;

        UPDATE tmp_ch_outside_unite_group_agg
           SET adj_qty = sum_qty;

        /* Взаимозачёт между Advanced_group внутри одного ERP_ID:
           отрицательные группы гасятся положительными группами.
           Отменяем только остаток, если после зачёта всё ещё < 0. */
        DROP TEMPORARY TABLE IF EXISTS tmp_ch_outside_unite_erp_queue;
        CREATE TEMPORARY TABLE tmp_ch_outside_unite_erp_queue (
            id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
            ERP_ID VARCHAR(255) NULL
        );

        INSERT INTO tmp_ch_outside_unite_erp_queue (ERP_ID)
        SELECT DISTINCT ERP_ID
        FROM tmp_ch_outside_unite_group_agg;

        net_loop: LOOP
            SELECT COUNT(*) INTO v_queue_left FROM tmp_ch_outside_unite_erp_queue;
            IF v_queue_left = 0 THEN
                LEAVE net_loop;
            END IF;

            SELECT id, ERP_ID INTO v_erp_row_id, v_erp_id
            FROM tmp_ch_outside_unite_erp_queue
            ORDER BY id
            LIMIT 1;

            SELECT COALESCE(SUM(ABS(adj_qty)), 0)
              INTO v_neg_left
            FROM tmp_ch_outside_unite_group_agg
            WHERE ERP_ID <=> v_erp_id
              AND adj_qty < 0;

            IF v_neg_left > 0 THEN
                /* Отрицательные группы временно обнуляем, далее гасим за счёт положительных. */
                UPDATE tmp_ch_outside_unite_group_agg
                   SET adj_qty = 0
                 WHERE ERP_ID <=> v_erp_id
                   AND sum_qty < 0;

                pos_loop: LOOP
                    IF v_neg_left <= 0 THEN
                        LEAVE pos_loop;
                    END IF;

                    SELECT COUNT(*) INTO v_queue_left
                    FROM tmp_ch_outside_unite_group_agg
                    WHERE ERP_ID <=> v_erp_id
                      AND adj_qty > 0;

                    IF v_queue_left = 0 THEN
                        LEAVE pos_loop;
                    END IF;

                    SELECT ag_key, adj_qty
                      INTO v_pos_ag_key, v_pos_qty
                    FROM tmp_ch_outside_unite_group_agg
                    WHERE ERP_ID <=> v_erp_id
                      AND adj_qty > 0
                    ORDER BY adj_qty DESC, ag_key
                    LIMIT 1;

                    SET v_take = LEAST(v_pos_qty, v_neg_left);

                    UPDATE tmp_ch_outside_unite_group_agg
                       SET adj_qty = adj_qty - v_take
                     WHERE ERP_ID <=> v_erp_id
                       AND ag_key = v_pos_ag_key;

                    SET v_neg_left = v_neg_left - v_take;
                END LOOP pos_loop;

                IF v_neg_left > 0 THEN
                    /* Остался непогашенный минус — отменяем только остаток. */
                    SELECT ag_key
                      INTO v_neg_ag_key
                    FROM tmp_ch_outside_unite_group_agg
                    WHERE ERP_ID <=> v_erp_id
                      AND sum_qty < 0
                    ORDER BY sum_qty ASC, ag_key
                    LIMIT 1;

                    UPDATE tmp_ch_outside_unite_group_agg
                       SET adj_qty = 0
                     WHERE ERP_ID <=> v_erp_id
                       AND sum_qty < 0;

                    UPDATE tmp_ch_outside_unite_group_agg
                       SET adj_qty = -v_neg_left
                     WHERE ERP_ID <=> v_erp_id
                       AND ag_key = v_neg_ag_key;
                END IF;
            END IF;

            DELETE FROM tmp_ch_outside_unite_erp_queue
            WHERE id = v_erp_row_id;
        END LOOP net_loop;

        DROP TEMPORARY TABLE IF EXISTS tmp_ch_outside_unite_erp_queue;

        /* 6) Дельта по Main:
              old_total = сумма партнёрских строк (is_incoming=0),
              incoming_total = сумма входящих строк (is_incoming=1),
              new_total = GREATEST(0, old_total + incoming_total),
              delta = new_total - old_total.
              Непокрытый отрицательный остаток (Отменено) в Main не попадает. */
        DROP TEMPORARY TABLE IF EXISTS tmp_ch_outside_unite_main_delta;
        DROP TEMPORARY TABLE IF EXISTS tmp_ch_outside_unite_partner_total;
        DROP TEMPORARY TABLE IF EXISTS tmp_ch_outside_unite_incoming_total;

        CREATE TEMPORARY TABLE tmp_ch_outside_unite_partner_total AS
        SELECT
            x.`ERP_ID` AS ERP_ID,
            COALESCE(SUM(x.`Quantity_change`), 0) AS old_partner_total
        FROM tmp_ch_outside_unite_ids x
        WHERE x.`is_incoming` = 0
        GROUP BY x.`ERP_ID`;

        CREATE TEMPORARY TABLE tmp_ch_outside_unite_incoming_total AS
        SELECT
            x.`ERP_ID` AS ERP_ID,
            COALESCE(SUM(x.`Quantity_change`), 0) AS incoming_total
        FROM tmp_ch_outside_unite_ids x
        WHERE x.`is_incoming` = 1
        GROUP BY x.`ERP_ID`;

        CREATE TEMPORARY TABLE tmp_ch_outside_unite_main_delta AS
        SELECT
            b.`ERP_ID` AS ERP_ID,
            GREATEST(
                0,
                COALESCE(p.`old_partner_total`, 0) + COALESCE(i.`incoming_total`, 0)
            ) - COALESCE(p.`old_partner_total`, 0) AS delta
        FROM (
            SELECT DISTINCT `ERP_ID` FROM tmp_ch_outside_unite_ids
        ) b
        LEFT JOIN tmp_ch_outside_unite_partner_total p
               ON p.`ERP_ID` = b.`ERP_ID`
        LEFT JOIN tmp_ch_outside_unite_incoming_total i
               ON i.`ERP_ID` = b.`ERP_ID`;

        /* Main: создать строку, если ещё нет */
        IF p_main_use_manufacturing = 0 THEN
            INSERT INTO `Main` (
                created_at,
                updated_at,
                created_by,
                updated_by,
                ERP_ID,
                Supplied_component_number,
                Component_revision,
                Component_name,
                Components_quantity_in_assembly,
                inProcess_purchase,
                Component_type,
                Part_material, Producer, Catalogue_number, Producer_article, Distributer,
                Distributer_article, MBOM_type, Mass_kg, Unit_of_measure, Height, Width, Length
            )
            SELECT
                NOW(),
                NOW(),
                p_proc_name,
                p_proc_name,
                t.ERP_ID,
                MIN(t.Supplied_component_number),
                MIN(t.Component_revision),
                MIN(t.Component_name),
                MIN(COALESCE(t.Components_quantity_in_assembly, 0)),
                0,
                MIN(t.Component_type),
                MIN(t.Part_material), MIN(t.Producer), MIN(t.Catalogue_number), MIN(t.Producer_article),
                MIN(t.Distributer), MIN(t.Distributer_article), MIN(t.MBOM_type), MIN(t.Mass_kg),
                MIN(t.Unit_of_measure), MIN(t.Height), MIN(t.Width), MIN(t.Length)
            FROM `Transactions` t
            INNER JOIN tmp_ch_outside_unite_ids x ON x.id = t.id AND x.`is_incoming` = 1
            WHERE NOT EXISTS (
                SELECT 1
                FROM `Main` m
                WHERE m.ERP_ID = t.ERP_ID
            )
            GROUP BY t.ERP_ID;

            UPDATE `Main` AS m
            INNER JOIN tmp_ch_outside_unite_main_delta d ON d.`ERP_ID` = m.`ERP_ID`
            SET
                m.`inProcess_purchase` = COALESCE(m.`inProcess_purchase`, 0) + d.`delta`,
                m.`updated_at`         = NOW(),
                m.`updated_by`         = p_proc_name;
        ELSE
            INSERT INTO `Main` (
                created_at,
                updated_at,
                created_by,
                updated_by,
                ERP_ID,
                Supplied_component_number,
                Component_revision,
                Component_name,
                Components_quantity_in_assembly,
                inProcess_manufacturing,
                Component_type,
                Part_material, Producer, Catalogue_number, Producer_article, Distributer,
                Distributer_article, MBOM_type, Mass_kg, Unit_of_measure, Height, Width, Length
            )
            SELECT
                NOW(),
                NOW(),
                p_proc_name,
                p_proc_name,
                t.ERP_ID,
                MIN(t.Supplied_component_number),
                MIN(t.Component_revision),
                MIN(t.Component_name),
                MIN(COALESCE(t.Components_quantity_in_assembly, 0)),
                0,
                MIN(t.Component_type),
                MIN(t.Part_material), MIN(t.Producer), MIN(t.Catalogue_number), MIN(t.Producer_article),
                MIN(t.Distributer), MIN(t.Distributer_article), MIN(t.MBOM_type), MIN(t.Mass_kg),
                MIN(t.Unit_of_measure), MIN(t.Height), MIN(t.Width), MIN(t.Length)
            FROM `Transactions` t
            INNER JOIN tmp_ch_outside_unite_ids x ON x.id = t.id AND x.`is_incoming` = 1
            WHERE NOT EXISTS (
                SELECT 1
                FROM `Main` m
                WHERE m.ERP_ID = t.ERP_ID
            )
            GROUP BY t.ERP_ID;

            UPDATE `Main` AS m
            INNER JOIN tmp_ch_outside_unite_main_delta d ON d.`ERP_ID` = m.`ERP_ID`
            SET
                m.`inProcess_manufacturing` = COALESCE(m.`inProcess_manufacturing`, 0) + d.`delta`,
                m.`updated_at`              = NOW(),
                m.`updated_by`              = p_proc_name;
        END IF;

        /*
         * Отмена без «фантомной» merge-строки с Quantity_change = 0:
         *  - cnt >= 2 и после неттинга adj_qty = 0 — одна сумма по группе 0, новую строку не создаём;
         *    исходные строки переводим в Отменено, Quantity_change с сохранением (для целостности).
         *  - cnt = 1 и adj_qty <= 0 — то же: только статусы, количество не перезаписываем.
         */
        UPDATE `Transactions` t
        INNER JOIN tmp_ch_outside_unite_ids x ON x.`id` = t.`id`
        INNER JOIN tmp_ch_outside_unite_group_agg g
          ON g.`ERP_ID` = x.`ERP_ID`
         AND g.`ag_key` = COALESCE(NULLIF(TRIM(x.`Advanced_group`), ''), '')
        SET
            t.`Status_transaction` = 'Отменено',
            t.`Status_warehouse`   = 'Норма',
            t.`Source`             = p_source,
            t.`updated_at`         = NOW(),
            t.`updated_by`         = CASE
                                        WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN p_proc_name
                                        ELSE CONCAT(t.`updated_by`, '; ', p_proc_name)
                                     END
        WHERE g.`cnt` >= 2
          AND COALESCE(g.`adj_qty`, 0) = 0;

        UPDATE `Transactions` t
        INNER JOIN tmp_ch_outside_unite_ids x ON x.`id` = t.`id`
        INNER JOIN tmp_ch_outside_unite_group_agg g
          ON g.`ERP_ID` = x.`ERP_ID`
         AND g.`ag_key` = COALESCE(NULLIF(TRIM(x.`Advanced_group`), ''), '')
        SET
            t.`Status_transaction` = 'Отменено',
            t.`Status_warehouse`   = 'Норма',
            t.`Source`             = p_source,
            t.`updated_at`         = NOW(),
            t.`updated_by`         = CASE
                                        WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN p_proc_name
                                        ELSE CONCAT(t.`updated_by`, '; ', p_proc_name)
                                     END
        WHERE g.`cnt` = 1
          AND COALESCE(g.`adj_qty`, 0) <= 0;

        /* 4) cnt >= 2 и нетто <> 0: одна суммарная строка, linked, Заменено (без вставки при adj_qty = 0) */
        DROP TEMPORARY TABLE IF EXISTS tmp_ch_outside_unite_replace_queue;
        CREATE TEMPORARY TABLE tmp_ch_outside_unite_replace_queue (
            `id` INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
            `ERP_ID` VARCHAR(255) NOT NULL,
            `ag_key` TEXT NOT NULL
        );

        INSERT INTO tmp_ch_outside_unite_replace_queue (`ERP_ID`, `ag_key`)
        SELECT `ERP_ID`, `ag_key`
        FROM tmp_ch_outside_unite_group_agg
        WHERE `cnt` >= 2
          AND COALESCE(`adj_qty`, 0) <> 0;

        replace_loop: LOOP
            SELECT COUNT(*) INTO v_queue_left FROM tmp_ch_outside_unite_replace_queue;
            IF v_queue_left = 0 THEN
                LEAVE replace_loop;
            END IF;

            SELECT `ERP_ID`, `ag_key` INTO v_erp_id, v_ag_key
            FROM tmp_ch_outside_unite_replace_queue
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
                g.`adj_qty`,
                CASE WHEN g.`adj_qty` <= 0 THEN 'Отменено' ELSE 'В ожидании' END,
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
                CASE WHEN g.`adj_qty` <= 0 THEN 'Норма' ELSE p_wh_merge END,
                fld.`Document_no`,
                fld.`Document_date`,
                fld.`Zakaz_no`, fld.`Date_needed`, fld.`Date_expected`, fld.`Cost_total_rub`,
                fld.`Supplier`, fld.`Location`, fld.`Source`, fld.`Initial_doc_no`,
                p_proc_name,
                p_proc_name,
                NOW(),
                NOW()
            FROM tmp_ch_outside_unite_group_agg g
            INNER JOIN (
                SELECT
                    t.`ERP_ID`,
                    COALESCE(NULLIF(TRIM(t.`Advanced_group`), ''), '') AS `ag_key`,
                    MIN(t.`Project`) AS `Project`,
                    MIN(t.`Target_assembly`) AS `Target_assembly`,
                    MIN(t.`Supplied_component_number`) AS `Supplied_component_number`,
                    MIN(t.`Component_revision`) AS `Component_revision`,
                    MIN(t.`Component_name`) AS `Component_name`,
                    MIN(t.`Quantity_in_target_assembly`) AS `Quantity_in_target_assembly`,
                    MIN(t.`Quantity_of_target_assemblies`) AS `Quantity_of_target_assemblies`,
                    MIN(t.`Components_quantity_in_assembly`) AS `Components_quantity_in_assembly`,
                    MIN(t.`Assembly_batch_id`) AS `Assembly_batch_id`,
                    MIN(t.`Assembly_batch_name`) AS `Assembly_batch_name`,
                    MIN(t.`Assembly_batch_status`) AS `Assembly_batch_status`,
                    MIN(t.`Assembly_batch_priority`) AS `Assembly_batch_priority`,
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
                    MIN(t.`Recommend_purchprod`) AS `Recommend_purchprod`,
                    MIN(t.`Document_no`) AS `Document_no`,
                    MIN(t.`Document_date`) AS `Document_date`,
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
                    MIN(t.`Order_OTK`) AS `Order_OTK`,
                    MIN(t.`Order_sv`) AS `Order_sv`,
                    MIN(t.`Recommend_wh`) AS `Recommend_wh`,
                    SUM(COALESCE(t.`Quantity_ordered`, 0)) AS `sum_qty_ord`,
                    MIN(t.`Replace_to`) AS `Replace_to`,
                    MIN(t.`Rework_to`) AS `Rework_to`,
                    MIN(t.`Rework_from`) AS `Rework_from`
                FROM `Transactions` t
                INNER JOIN tmp_ch_outside_unite_ids x ON x.`id` = t.`id`
                GROUP BY t.`ERP_ID`, COALESCE(NULLIF(TRIM(t.`Advanced_group`), ''), '')
            ) fld
              ON fld.`ERP_ID` = g.`ERP_ID`
             AND fld.`ag_key` = g.`ag_key`
            WHERE g.`cnt` >= 2
              AND COALESCE(g.`adj_qty`, 0) <> 0
              AND g.`ERP_ID` = v_erp_id
              AND g.`ag_key` = v_ag_key;

            SET v_new_id = LAST_INSERT_ID();

            UPDATE `Transactions` t
            SET
                t.`linked_transaction` = CASE
                    WHEN t.`linked_transaction` IS NULL OR TRIM(COALESCE(t.`linked_transaction`, '')) = '' THEN CAST(v_new_id AS CHAR)
                    ELSE CONCAT(TRIM(t.`linked_transaction`), '; ', v_new_id)
                END,
                t.`updated_at`         = NOW(),
                t.`updated_by`         = CASE
                                            WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN p_proc_name
                                            ELSE CONCAT(t.`updated_by`, '; ', p_proc_name)
                                         END
            WHERE t.`id` = v_new_id;

            UPDATE `Transactions` t
            INNER JOIN tmp_ch_outside_unite_ids x ON x.id = t.id
            INNER JOIN tmp_ch_outside_unite_group_agg g
              ON g.`ERP_ID` = x.`ERP_ID`
             AND g.`ag_key` = COALESCE(NULLIF(TRIM(x.`Advanced_group`), ''), '')
            SET
                t.`linked_transaction` = CASE
                    WHEN t.`linked_transaction` IS NULL OR TRIM(COALESCE(t.`linked_transaction`, '')) = '' THEN CAST(v_new_id AS CHAR)
                    ELSE CONCAT(TRIM(t.`linked_transaction`), '; ', v_new_id)
                END,
                t.`Status_transaction` = 'Заменено',
                t.`Status_warehouse`   = 'Норма',
                t.`Source`             = p_source,
                t.`updated_at`         = NOW(),
                t.`updated_by`         = CASE
                                            WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN p_proc_name
                                            ELSE CONCAT(t.`updated_by`, '; ', p_proc_name)
                                         END
            WHERE g.`cnt` >= 2
              AND COALESCE(g.`adj_qty`, 0) <> 0
              AND g.`ERP_ID` = v_erp_id
              AND g.`ag_key` = v_ag_key;

            DELETE FROM tmp_ch_outside_unite_replace_queue
            WHERE `ERP_ID` = v_erp_id AND `ag_key` <=> v_ag_key;
        END LOOP replace_loop;

        DROP TEMPORARY TABLE IF EXISTS tmp_ch_outside_unite_replace_queue;

        /* 5) Одиночные строки */
        UPDATE `Transactions` t
        INNER JOIN tmp_ch_outside_unite_ids x ON x.id = t.id
        INNER JOIN tmp_ch_outside_unite_group_agg g
          ON g.`ERP_ID` = x.`ERP_ID`
         AND g.`ag_key` = COALESCE(NULLIF(TRIM(x.`Advanced_group`), ''), '')
        SET
            t.`Quantity_change` = g.`adj_qty`,
            t.`Status_transaction` = CASE
                WHEN COALESCE(g.`adj_qty`, 0) <= 0 THEN 'Отменено'
                ELSE 'В ожидании'
            END,
            t.`Status_warehouse` = CASE
                WHEN COALESCE(g.`adj_qty`, 0) <= 0 THEN 'Норма'
                ELSE p_wh_single
            END,
            t.`Source`     = p_source,
            t.`updated_at` = NOW(),
            t.`updated_by` = CASE
                                WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN p_proc_name
                                ELSE CONCAT(t.`updated_by`, '; ', p_proc_name)
                             END
        WHERE g.`cnt` = 1
          AND COALESCE(g.`adj_qty`, 0) > 0;

        /* cnt = 1 и adj_qty > 0: количество приводим к нетто; отменённые одиночные строки уже обработаны выше без смены Quantity_change */

        DROP TEMPORARY TABLE IF EXISTS tmp_ch_outside_unite_main_delta;
        DROP TEMPORARY TABLE IF EXISTS tmp_ch_outside_unite_partner_total;
        DROP TEMPORARY TABLE IF EXISTS tmp_ch_outside_unite_incoming_total;
        DROP TEMPORARY TABLE IF EXISTS tmp_ch_outside_unite_group_agg;
        DROP TEMPORARY TABLE IF EXISTS tmp_ch_outside_unite_ids;

        COMMIT;
        DO RELEASE_LOCK(@ch_outside_unite_lock);
    END IF;
END$$

DELIMITER ;
