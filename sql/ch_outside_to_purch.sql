-- ch_outside_to_purch: передача change «внешний → склад» в закупку (Order_purch «В закупке»/«Оплачено» и Order_prod = «В закупку»).
-- Блокировка: lock_process_purchase_change_to_main
-- Убедитесь, что значение «В закупку» есть в enum Order_prod в вашей БД.
--
-- Алгоритм:
-- 1) Отбор change (входящие: Новая / Дефицит закупки + подтягивание уже «В закупке»/«В ожидании» той же пары ERP_ID + Advanced_group для неттинга). Строки «Исполнено» в выборку не входят.
-- 2) Всем отобранным строкам: Status_warehouse = «В закупке».
-- 3) Группировка по (ERP_ID, Advanced_group), сумма Quantity_change.
-- 4) Группы с двумя и более строками: сначала вставка одной суммарной change; у старых строк linked_transaction = id новой,
--    created_by = имя процедуры; у новой строки linked_transaction = собственный id; затем старые → «Заменено», склад «Норма».
--    При сумме 0 → Status_transaction «Отменено», склад «Норма»; иначе → «В ожидании», склад «В закупке».
-- 5) Группа из одной строки: без замены; при qty = 0 — «Отменено»/«Норма»; при qty <> 0 — «В ожидании»/«В закупке» (в т.ч. отрицательные qty).
-- 6) Main.inProcess_purchase: для групп с заменой += (сумма по группе − сумма по «входящим» строкам группы); для одиночных «входящих» += Quantity_change как раньше.
-- Требуется MySQL 8+ (для подзапросов в CREATE AS SELECT при необходимости).
--
-- phpMyAdmin: выполните весь скрипт целиком (вкладка SQL). Ниже DELIMITER $$ — без него
-- клиент режет по «;» внутри BEGIN…END и процедура не создаётся.

DELIMITER $$

DROP PROCEDURE IF EXISTS ch_outside_to_purch$$

CREATE PROCEDURE ch_outside_to_purch()
BEGIN
    DECLARE v_lock_ok INT DEFAULT 0;
    DECLARE v_erp_id VARCHAR(255);
    DECLARE v_ag_key TEXT;
    DECLARE v_new_id INT UNSIGNED;
    DECLARE v_queue_left INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        IF v_lock_ok = 1 THEN
            DO RELEASE_LOCK('lock_process_purchase_change_to_main');
        END IF;
        RESIGNAL;
    END;

    SELECT GET_LOCK('lock_process_purchase_change_to_main', 0) INTO v_lock_ok;

    IF v_lock_ok = 1 THEN
        START TRANSACTION;

        DROP TEMPORARY TABLE IF EXISTS tmp_purch_change_ids;
        CREATE TEMPORARY TABLE tmp_purch_change_ids (
            id INT UNSIGNED PRIMARY KEY,
            ERP_ID VARCHAR(255) NOT NULL,
            Advanced_group TEXT NULL,
            Quantity_change BIGINT NOT NULL,
            is_incoming TINYINT(1) NOT NULL
        );

        /* Входящий батч: Новая / Дефицит закупки */
        INSERT INTO tmp_purch_change_ids (id, ERP_ID, Advanced_group, Quantity_change, is_incoming)
        SELECT
            t.id,
            t.ERP_ID,
            t.Advanced_group,
            COALESCE(t.Quantity_change, 0),
            1
        FROM `Transactions` t
        WHERE t.Status_warehouse IN ('Новая', 'Дефицит закупки')
          AND t.Order_purch IN ('В закупке', 'Оплачено')
          AND t.Order_prod = 'В закупку'
          AND t.type = 'change'
          AND t.where_from = 'внешний'
          AND t.where_to = 'склад';

        /* Уже в закупке, «В ожидании», та же пара ERP_ID + Advanced_group — для неттинга (#1137: не INSERT INTO tmp FROM tmp в одном запросе). */
        DROP TEMPORARY TABLE IF EXISTS tmp_purch_ids_snapshot;
        CREATE TEMPORARY TABLE tmp_purch_ids_snapshot AS
        SELECT id FROM tmp_purch_change_ids;

        DROP TEMPORARY TABLE IF EXISTS tmp_purch_partner_pick;
        CREATE TEMPORARY TABLE tmp_purch_partner_pick AS
        SELECT DISTINCT
            t.id,
            t.ERP_ID,
            t.Advanced_group,
            COALESCE(t.Quantity_change, 0) AS Quantity_change,
            0 AS is_incoming
        FROM tmp_purch_change_ids x
        INNER JOIN `Transactions` t
          ON t.`ERP_ID` = x.`ERP_ID`
         AND (t.`Advanced_group` <=> x.`Advanced_group`)
         AND t.`id` <> x.`id`
        LEFT JOIN tmp_purch_ids_snapshot snap ON snap.id = t.id
        WHERE x.`is_incoming` = 1
          AND t.`type` = 'change'
          AND t.`where_from` = 'внешний'
          AND t.`where_to` = 'склад'
          AND t.`Order_purch` IN ('В закупке', 'Оплачено')
          AND t.`Order_prod` = 'В закупку'
          AND t.`Status_warehouse` = 'В закупке'
          AND t.`Status_transaction` = 'В ожидании'
          AND COALESCE(t.`Quantity_change`, 0) <> 0
          AND snap.id IS NULL;

        INSERT INTO tmp_purch_change_ids (id, ERP_ID, Advanced_group, Quantity_change, is_incoming)
        SELECT id, ERP_ID, Advanced_group, Quantity_change, is_incoming FROM tmp_purch_partner_pick;

        DROP TEMPORARY TABLE IF EXISTS tmp_purch_partner_pick;
        DROP TEMPORARY TABLE IF EXISTS tmp_purch_ids_snapshot;

        /* 2) Всем отобранным: склад «В закупке» */
        UPDATE `Transactions` t
        INNER JOIN tmp_purch_change_ids x ON x.id = t.id
        SET
            t.`Status_warehouse` = 'В закупке',
            t.`updated_at`       = NOW(),
            t.`updated_by`       = 'ch_outside_to_purch';

        /* 3) Агрегаты по группам */
        DROP TEMPORARY TABLE IF EXISTS tmp_purch_group_agg;
        CREATE TEMPORARY TABLE tmp_purch_group_agg AS
        SELECT
            x.`ERP_ID` AS ERP_ID,
            COALESCE(x.`Advanced_group`, '') AS ag_key,
            COUNT(*) AS cnt,
            SUM(x.`Quantity_change`) AS sum_qty,
            SUM(CASE WHEN x.`is_incoming` = 1 THEN x.`Quantity_change` ELSE 0 END) AS sum_incoming
        FROM tmp_purch_change_ids x
        GROUP BY x.`ERP_ID`, COALESCE(x.`Advanced_group`, '');

        /* 6) Дельта по Main: замена — (сумма группы − вклад входящих); одиночная строка — только если is_incoming */
        DROP TEMPORARY TABLE IF EXISTS tmp_purch_main_delta;
        CREATE TEMPORARY TABLE tmp_purch_main_delta AS
        SELECT
            u.`ERP_ID` AS ERP_ID,
            SUM(u.`delta`) AS delta
        FROM (
            SELECT
                g.`ERP_ID` AS ERP_ID,
                CASE
                    WHEN g.`cnt` >= 2 THEN g.`sum_qty` - g.`sum_incoming`
                    ELSE (
                        SELECT CASE WHEN x.`is_incoming` = 1 THEN x.`Quantity_change` ELSE 0 END
                        FROM tmp_purch_change_ids x
                        WHERE x.`ERP_ID` = g.`ERP_ID`
                          AND COALESCE(x.`Advanced_group`, '') = g.`ag_key`
                        LIMIT 1
                    )
                END AS delta
            FROM tmp_purch_group_agg g
        ) u
        GROUP BY u.`ERP_ID`;

        /* Main: создать строку, если ещё нет (поля из минимального id в группе входящих) */
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
            'ch_outside_to_purch',
            'ch_outside_to_purch',
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
        INNER JOIN tmp_purch_change_ids x ON x.id = t.id AND x.`is_incoming` = 1
        WHERE NOT EXISTS (
            SELECT 1
            FROM `Main` m
            WHERE m.ERP_ID = t.ERP_ID
        )
        GROUP BY t.ERP_ID;

        UPDATE `Main` AS m
        INNER JOIN tmp_purch_main_delta d ON d.`ERP_ID` = m.`ERP_ID`
        SET
            m.`inProcess_purchase` = COALESCE(m.`inProcess_purchase`, 0) + d.`delta`,
            m.`updated_at`       = NOW(),
            m.`updated_by`       = 'ch_outside_to_purch';

        /* 4) По группам cnt >= 2: вставка суммарной строки → LAST_INSERT_ID → старым linked + created_by; новой linked = id; затем «Заменено» */
        DROP TEMPORARY TABLE IF EXISTS tmp_purch_replace_queue;
        CREATE TEMPORARY TABLE tmp_purch_replace_queue (
            `id` INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
            `ERP_ID` VARCHAR(255) NOT NULL,
            `ag_key` TEXT NOT NULL
        );

        INSERT INTO tmp_purch_replace_queue (`ERP_ID`, `ag_key`)
        SELECT `ERP_ID`, `ag_key` FROM tmp_purch_group_agg WHERE `cnt` >= 2;

        replace_loop: LOOP
            SELECT COUNT(*) INTO v_queue_left FROM tmp_purch_replace_queue;
            IF v_queue_left = 0 THEN
                LEAVE replace_loop;
            END IF;

            SELECT `ERP_ID`, `ag_key` INTO v_erp_id, v_ag_key
            FROM tmp_purch_replace_queue
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
                Order_purch, Order_wh, Order_prod, Order_OTK, Status_warehouse,
                Document_no, Zakaz_no, Date_needed, Date_expected, Cost_total_rub,
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
                CASE WHEN g.`sum_qty` = 0 THEN 'Отменено' ELSE 'В ожидании' END,
                tmpl.`Project`, tmpl.`Target_assembly`, tmpl.`Supplied_component_number`, tmpl.`Component_revision`, tmpl.`Component_name`,
                tmpl.`Quantity_in_target_assembly`, tmpl.`Quantity_of_target_assemblies`, tmpl.`Components_quantity_in_assembly`,
                tmpl.`Component_type`, tmpl.`For_supplied_as_assembly_components_provided_by_supplier`, tmpl.`Part_material`,
                tmpl.`Producer`, tmpl.`Catalogue_number`, tmpl.`Producer_article`, tmpl.`Distributer`, tmpl.`Distributer_article`,
                tmpl.`MBOM_type`, tmpl.`Mass_kg`, tmpl.`Unit_of_measure`, tmpl.`Height`, tmpl.`Width`, tmpl.`Length`,
                tmpl.`Advanced_group`, tmpl.`Address`,
                tmpl.`Order_purch`,
                NULL,
                tmpl.`Order_prod`,
                tmpl.`Order_OTK`,
                CASE WHEN g.`sum_qty` = 0 THEN 'Норма' ELSE 'В закупке' END,
                tmpl.`Document_no`, tmpl.`Zakaz_no`, tmpl.`Date_needed`, tmpl.`Date_expected`, tmpl.`Cost_total_rub`,
                'ch_outside_to_purch',
                'ch_outside_to_purch',
                NOW(),
                NOW()
            FROM tmp_purch_group_agg g
            INNER JOIN (
                SELECT
                    t.`ERP_ID`,
                    COALESCE(t.`Advanced_group`, '') AS ag_key,
                    MIN(t.`id`) AS min_id
                FROM `Transactions` t
                INNER JOIN tmp_purch_change_ids x ON x.id = t.id
                GROUP BY t.`ERP_ID`, COALESCE(t.`Advanced_group`, '')
            ) pick
              ON pick.`ERP_ID` = g.`ERP_ID`
             AND pick.`ag_key` = g.`ag_key`
            INNER JOIN `Transactions` tmpl ON tmpl.`id` = pick.`min_id`
            WHERE g.`cnt` >= 2
              AND g.`ERP_ID` = v_erp_id
              AND g.`ag_key` = v_ag_key;

            SET v_new_id = LAST_INSERT_ID();

            UPDATE `Transactions` t
            SET
                t.`linked_transaction` = v_new_id,
                t.`updated_at`         = NOW(),
                t.`updated_by`         = 'ch_outside_to_purch'
            WHERE t.`id` = v_new_id;

            UPDATE `Transactions` t
            INNER JOIN tmp_purch_change_ids x ON x.id = t.id
            INNER JOIN tmp_purch_group_agg g
              ON g.`ERP_ID` = x.`ERP_ID`
             AND g.`ag_key` = COALESCE(x.`Advanced_group`, '')
            SET
                t.`linked_transaction` = v_new_id,
                t.`created_by`         = 'ch_outside_to_purch',
                t.`Status_transaction` = 'Заменено',
                t.`Status_warehouse`   = 'Норма',
                t.`updated_at`         = NOW(),
                t.`updated_by`         = 'ch_outside_to_purch'
            WHERE g.`cnt` >= 2
              AND g.`ERP_ID` = v_erp_id
              AND g.`ag_key` = v_ag_key;

            DELETE FROM tmp_purch_replace_queue
            WHERE `ERP_ID` = v_erp_id AND `ag_key` <=> v_ag_key;
        END LOOP replace_loop;

        DROP TEMPORARY TABLE IF EXISTS tmp_purch_replace_queue;

        /* 5) Одиночные строки: без новой вставки, только статусы */
        UPDATE `Transactions` t
        INNER JOIN tmp_purch_change_ids x ON x.id = t.id
        INNER JOIN tmp_purch_group_agg g
          ON g.`ERP_ID` = x.`ERP_ID`
         AND g.`ag_key` = COALESCE(x.`Advanced_group`, '')
        SET
            t.`Status_transaction` = CASE
                WHEN COALESCE(x.`Quantity_change`, 0) = 0 THEN 'Отменено'
                ELSE 'В ожидании'
            END,
            t.`Status_warehouse` = CASE
                WHEN COALESCE(x.`Quantity_change`, 0) = 0 THEN 'Норма'
                ELSE 'В закупке'
            END,
            t.`updated_at` = NOW(),
            t.`updated_by` = 'ch_outside_to_purch'
        WHERE g.`cnt` = 1;

        /* 7) Для ERP_ID, взятых в закупку, перевести move "Ожидание поставки" -> "Новая" */
        UPDATE `Transactions` t
        INNER JOIN (
            SELECT DISTINCT x.`ERP_ID`
            FROM tmp_purch_change_ids x
        ) e ON e.`ERP_ID` = t.`ERP_ID`
        SET
            t.`Status_warehouse` = 'Новая',
            t.`updated_at`       = NOW(),
            t.`updated_by`       = 'ch_outside_to_purch'
        WHERE t.`type` = 'move'
          AND t.`where_from` = 'склад'
          AND t.`where_to` IN ('брак', 'отгрузка', 'изделие')
          AND t.`Status_transaction` = 'В ожидании'
          AND t.`Status_warehouse` = 'Ожидание поставки';

        DROP TEMPORARY TABLE IF EXISTS tmp_purch_main_delta;
        DROP TEMPORARY TABLE IF EXISTS tmp_purch_group_agg;
        DROP TEMPORARY TABLE IF EXISTS tmp_purch_change_ids;

        COMMIT;
        DO RELEASE_LOCK('lock_process_purchase_change_to_main');
    END IF;
END$$

DELIMITER ;
