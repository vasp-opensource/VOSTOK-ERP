-- deficit: разбор move «склад → брак / отгрузка / изделие» при дефиците склада: распределение по складу / изготовлению / закупке и накопление change по дефициту.
-- Новые строки копируют карточку номенклатуры/документов с исходного move (в т.ч. Initial_doc_no); см. alter_transactions_Initial_doc_no.sql.
-- Блокировка: lock_process_move_deficit_wh_to_shop (ожидание до 30 с).
-- Потребность в change: move «Дефицит закупки» в «В ожидании»; qty = GREATEST(parts_total, quantity_change).
-- Вычет covered_qty: уже учтённые change «внешний→склад» по закупке — все, кроме «Отменено»/«Заменено»
-- (в т.ч. «В ожидании» и уже «Исполнено» после ch_purch_to_wh с Норма на складе). Иначе исполненная заявка
-- не входила в вычет, и deficit снова добавлял полный need_qty → тройное заказывание при слиянии ch_outside_*.
-- Часть со склада в комплектацию (Order_wh «В комплектации»): Status_warehouse = «Комплектация».
--
-- Source: «Покупное», «Собственное производство», «Разные», NULL/пусто (как после объединений).
-- Потребность строки — как в move_wh_to_shopfloor: при нулевом Quantity_of_parts_total берётся Quantity_change.
-- Для закупки и NULL при создании change: Status_warehouse = «Дефицит закупки».
-- where_to только: «брак», «отгрузка», «изделие» (значение «цех» не обрабатывается). Порядок обхода: брак → отгрузка → изделие.
-- Колонки Imported и nc_order в INSERT не используются.

DELIMITER $$

DROP PROCEDURE IF EXISTS deficit$$

CREATE PROCEDURE deficit()
BEGIN
    DECLARE done INT DEFAULT 0;
    DECLARE v_lock_ok INT DEFAULT 0;

    DECLARE v_tx_id INT;
    DECLARE v_erp_id VARCHAR(255);
    DECLARE v_req_qty BIGINT;
    DECLARE v_adv_group TEXT;

    DECLARE v_stock BIGINT DEFAULT 0;
    DECLARE v_prod_total BIGINT DEFAULT 0;
    DECLARE v_purch_total BIGINT DEFAULT 0;

    DECLARE v_prod_reserved BIGINT DEFAULT 0;
    DECLARE v_purch_reserved BIGINT DEFAULT 0;

    DECLARE v_prod_free BIGINT DEFAULT 0;
    DECLARE v_purch_free BIGINT DEFAULT 0;

    DECLARE v_part_stock BIGINT DEFAULT 0;
    DECLARE v_part_prod BIGINT DEFAULT 0;
    DECLARE v_part_purch BIGINT DEFAULT 0;
    DECLARE v_part_def BIGINT DEFAULT 0;
    DECLARE v_rest BIGINT DEFAULT 0;

    DECLARE cur CURSOR FOR
        SELECT
            t.id,
            t.ERP_ID,
            IF(
                COALESCE(t.`Quantity_of_parts_total`, 0) > 0,
                t.`Quantity_of_parts_total`,
                COALESCE(t.`Quantity_change`, 0)
            ) AS need_qty,
            t.Advanced_group
        FROM `Transactions` t
        WHERE t.type = 'move'
          AND t.where_from = 'склад'
          AND t.where_to IN ('брак', 'отгрузка', 'изделие')
          AND (
               t.Source IS NULL
            OR TRIM(COALESCE(t.Source, '')) = ''
            OR t.Source IN ('Покупное', 'Собственное производство', 'Разные')
          )
          AND (
               t.Status_transaction IS NULL
            OR TRIM(COALESCE(t.Status_transaction, '')) = ''
            OR t.Status_transaction = 'В ожидании'
          )
          AND (
               t.`Status_warehouse` = 'Дефицит склада'
            OR TRIM(t.`Status_warehouse`) = 'Дефицит склада'
          )
        ORDER BY FIELD(t.where_to, 'брак', 'отгрузка', 'изделие'), t.ERP_ID, t.id;

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        IF v_lock_ok = 1 THEN
            DO RELEASE_LOCK('lock_process_move_deficit_wh_to_shop');
        END IF;
        RESIGNAL;
    END;

    SELECT GET_LOCK('lock_process_move_deficit_wh_to_shop', 30) INTO v_lock_ok;

    IF v_lock_ok = 1 THEN
        START TRANSACTION;

        DROP TEMPORARY TABLE IF EXISTS tmp_deficit_accum;
        CREATE TEMPORARY TABLE tmp_deficit_accum (
            erp_id VARCHAR(255) NOT NULL,
            advanced_group TEXT NULL,
            qty BIGINT NOT NULL,
            src_tag VARCHAR(255) NOT NULL
        );

        OPEN cur;

        read_loop: LOOP
            FETCH cur INTO v_tx_id, v_erp_id, v_req_qty, v_adv_group;
            IF done = 1 THEN
                LEAVE read_loop;
            END IF;

            IF v_req_qty <= 0 THEN
                ITERATE read_loop;
            END IF;

            SELECT
                COALESCE(SUM(m.Quantity_in_warehouse), 0),
                COALESCE(SUM(m.inProcess_manufacturing), 0),
                COALESCE(SUM(m.inProcess_purchase), 0)
            INTO
                v_stock, v_prod_total, v_purch_total
            FROM `Main` m
            WHERE m.ERP_ID = v_erp_id;

            SELECT COALESCE(SUM(COALESCE(t.Quantity_of_parts_total, 0)), 0)
              INTO v_prod_reserved
            FROM `Transactions` t
            WHERE t.ERP_ID = v_erp_id
              AND t.type = 'move'
              AND t.Status_transaction = 'В ожидании'
              AND t.Status_warehouse = 'Ожидание изготовления';

            SELECT COALESCE(SUM(COALESCE(t.Quantity_of_parts_total, 0)), 0)
              INTO v_purch_reserved
            FROM `Transactions` t
            WHERE t.ERP_ID = v_erp_id
              AND t.type = 'move'
              AND t.Status_transaction = 'В ожидании'
              AND t.Status_warehouse = 'Ожидание закупки';

            SET v_prod_free = GREATEST(v_prod_total - v_prod_reserved, 0);
            SET v_purch_free = GREATEST(v_purch_total - v_purch_reserved, 0);

            UPDATE `Transactions`
               SET Status_warehouse   = 'Норма',
                   Status_transaction = 'Заменено',
                   linked_transaction   = CASE
                       WHEN `linked_transaction` IS NULL OR TRIM(COALESCE(`linked_transaction`, '')) = '' THEN CAST(v_tx_id AS CHAR)
                       ELSE CONCAT(TRIM(`linked_transaction`), '; ', v_tx_id)
                   END,
                  updated_by         = CASE
                                           WHEN `updated_by` IS NULL OR TRIM(COALESCE(`updated_by`, '')) = '' THEN 'deficit'
                                           ELSE CONCAT(`updated_by`, '; ', 'deficit')
                                       END,
                   updated_at         = CURRENT_TIMESTAMP
             WHERE id = v_tx_id;

            SET v_part_stock = LEAST(v_stock, v_req_qty);
            SET v_rest = v_req_qty - v_part_stock;

            SET v_part_prod = LEAST(v_prod_free, v_rest);
            SET v_rest = v_rest - v_part_prod;

            SET v_part_purch = LEAST(v_purch_free, v_rest);
            SET v_rest = v_rest - v_part_purch;

            SET v_part_def = v_rest;

            IF v_part_stock > 0 THEN
                INSERT INTO `Transactions` (
                    ERP_ID, created_at, updated_at, created_by, updated_by, linked_transaction,
                    type, where_from, where_to, Quantity_of_parts_total, Quantity_change, Status_transaction,
                    Project, Target_assembly, Supplied_component_number, Component_revision, Component_name,
                    Quantity_in_target_assembly, Quantity_of_target_assemblies, Components_quantity_in_assembly, Component_type,
                    For_supplied_as_assembly_components_provided_by_supplier, Part_material, Producer, Catalogue_number,
                    Producer_article, Distributer, Distributer_article, MBOM_type, Mass_kg, Unit_of_measure,
                    Height, Width, Length, Advanced_group, Address,
                    Document_no, Zakaz_no, Date_needed, Date_expected, Cost_total_rub,
                    Supplier, Location, Source, Initial_doc_no,
                    Order_purch, Order_wh, Order_prod, Order_OTK,
                    Status_warehouse
                )
                SELECT
                    t.ERP_ID, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 'deficit', 'deficit',
                    CASE
                        WHEN t.`linked_transaction` IS NULL OR TRIM(COALESCE(t.`linked_transaction`, '')) = '' THEN CAST(v_tx_id AS CHAR)
                        ELSE CONCAT(TRIM(t.`linked_transaction`), '; ', v_tx_id)
                    END,
                    'move', t.where_from, t.where_to, v_part_stock, 0, 'В ожидании',
                    t.Project, t.Target_assembly, t.Supplied_component_number, t.Component_revision, t.Component_name,
                    t.Quantity_in_target_assembly, t.Quantity_of_target_assemblies, t.Components_quantity_in_assembly, t.Component_type,
                    t.For_supplied_as_assembly_components_provided_by_supplier, t.Part_material, t.Producer, t.Catalogue_number,
                    t.Producer_article, t.Distributer, t.Distributer_article, t.MBOM_type, t.Mass_kg, t.Unit_of_measure,
                    t.Height, t.Width, t.Length, t.Advanced_group, t.Address,
                    t.Document_no, t.Zakaz_no, t.Date_needed, t.Date_expected, t.Cost_total_rub,
                    t.Supplier, t.Location, t.Source, t.Initial_doc_no,
                    t.Order_purch, 'В комплектации', t.Order_prod, t.Order_OTK,
                    'Комплектация'
                FROM `Transactions` t
                WHERE t.id = v_tx_id;

                UPDATE `Main`
                   SET Quantity_in_warehouse = Quantity_in_warehouse - v_part_stock,
                       Quantity_in_kitting   = COALESCE(Quantity_in_kitting, 0) + v_part_stock,
                      updated_by            = 'deficit',
                       updated_at            = CURRENT_TIMESTAMP
                 WHERE ERP_ID = v_erp_id;
            END IF;

            IF v_part_prod > 0 THEN
                INSERT INTO `Transactions` (
                    ERP_ID, created_at, updated_at, created_by, updated_by, linked_transaction,
                    type, where_from, where_to, Quantity_of_parts_total, Quantity_change, Status_transaction,
                    Project, Target_assembly, Supplied_component_number, Component_revision, Component_name,
                    Quantity_in_target_assembly, Quantity_of_target_assemblies, Components_quantity_in_assembly, Component_type,
                    For_supplied_as_assembly_components_provided_by_supplier, Part_material, Producer, Catalogue_number,
                    Producer_article, Distributer, Distributer_article, MBOM_type, Mass_kg, Unit_of_measure,
                    Height, Width, Length, Advanced_group, Address,
                    Document_no, Zakaz_no, Date_needed, Date_expected, Cost_total_rub,
                    Supplier, Location, Source, Initial_doc_no,
                    Order_purch, Order_wh, Order_prod, Order_OTK,
                    Status_warehouse
                )
                SELECT
                    t.ERP_ID, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 'deficit', 'deficit',
                    CASE
                        WHEN t.`linked_transaction` IS NULL OR TRIM(COALESCE(t.`linked_transaction`, '')) = '' THEN CAST(v_tx_id AS CHAR)
                        ELSE CONCAT(TRIM(t.`linked_transaction`), '; ', v_tx_id)
                    END,
                    'move', t.where_from, t.where_to, v_part_prod, 0, 'В ожидании',
                    t.Project, t.Target_assembly, t.Supplied_component_number, t.Component_revision, t.Component_name,
                    t.Quantity_in_target_assembly, t.Quantity_of_target_assemblies, t.Components_quantity_in_assembly, t.Component_type,
                    t.For_supplied_as_assembly_components_provided_by_supplier, t.Part_material, t.Producer, t.Catalogue_number,
                    t.Producer_article, t.Distributer, t.Distributer_article, t.MBOM_type, t.Mass_kg, t.Unit_of_measure,
                    t.Height, t.Width, t.Length, t.Advanced_group, t.Address,
                    t.Document_no, t.Zakaz_no, t.Date_needed, t.Date_expected, t.Cost_total_rub,
                    t.Supplier, t.Location, t.Source, t.Initial_doc_no,
                    t.Order_purch, NULL, t.Order_prod, t.Order_OTK,
                    'Ожидание изготовления'
                FROM `Transactions` t
                WHERE t.id = v_tx_id;
            END IF;

            IF v_part_purch > 0 THEN
                INSERT INTO `Transactions` (
                    ERP_ID, created_at, updated_at, created_by, updated_by, linked_transaction,
                    type, where_from, where_to, Quantity_of_parts_total, Quantity_change, Status_transaction,
                    Project, Target_assembly, Supplied_component_number, Component_revision, Component_name,
                    Quantity_in_target_assembly, Quantity_of_target_assemblies, Components_quantity_in_assembly, Component_type,
                    For_supplied_as_assembly_components_provided_by_supplier, Part_material, Producer, Catalogue_number,
                    Producer_article, Distributer, Distributer_article, MBOM_type, Mass_kg, Unit_of_measure,
                    Height, Width, Length, Advanced_group, Address,
                    Document_no, Zakaz_no, Date_needed, Date_expected, Cost_total_rub,
                    Supplier, Location, Source, Initial_doc_no,
                    Order_purch, Order_wh, Order_prod, Order_OTK,
                    Status_warehouse
                )
                SELECT
                    t.ERP_ID, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 'deficit', 'deficit',
                    CASE
                        WHEN t.`linked_transaction` IS NULL OR TRIM(COALESCE(t.`linked_transaction`, '')) = '' THEN CAST(v_tx_id AS CHAR)
                        ELSE CONCAT(TRIM(t.`linked_transaction`), '; ', v_tx_id)
                    END,
                    'move', t.where_from, t.where_to, v_part_purch, 0, 'В ожидании',
                    t.Project, t.Target_assembly, t.Supplied_component_number, t.Component_revision, t.Component_name,
                    t.Quantity_in_target_assembly, t.Quantity_of_target_assemblies, t.Components_quantity_in_assembly, t.Component_type,
                    t.For_supplied_as_assembly_components_provided_by_supplier, t.Part_material, t.Producer, t.Catalogue_number,
                    t.Producer_article, t.Distributer, t.Distributer_article, t.MBOM_type, t.Mass_kg, t.Unit_of_measure,
                    t.Height, t.Width, t.Length, t.Advanced_group, t.Address,
                    t.Document_no, t.Zakaz_no, t.Date_needed, t.Date_expected, t.Cost_total_rub,
                    t.Supplier, t.Location, t.Source, t.Initial_doc_no,
                    'Ожидание закупки', NULL, t.Order_prod, t.Order_OTK,
                    'Ожидание закупки'
                FROM `Transactions` t
                WHERE t.id = v_tx_id;
            END IF;

            IF v_part_def > 0 THEN
                INSERT INTO `Transactions` (
                    ERP_ID, created_at, updated_at, created_by, updated_by, linked_transaction,
                    type, where_from, where_to, Quantity_of_parts_total, Quantity_change, Status_transaction,
                    Project, Target_assembly, Supplied_component_number, Component_revision, Component_name,
                    Quantity_in_target_assembly, Quantity_of_target_assemblies, Components_quantity_in_assembly, Component_type,
                    For_supplied_as_assembly_components_provided_by_supplier, Part_material, Producer, Catalogue_number,
                    Producer_article, Distributer, Distributer_article, MBOM_type, Mass_kg, Unit_of_measure,
                    Height, Width, Length, Advanced_group, Address,
                    Document_no, Zakaz_no, Date_needed, Date_expected, Cost_total_rub,
                    Supplier, Location, Source, Initial_doc_no,
                    Order_purch, Order_wh, Order_prod, Order_OTK,
                    Status_warehouse
                )
                SELECT
                    t.ERP_ID, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 'deficit', 'deficit',
                    CASE
                        WHEN t.`linked_transaction` IS NULL OR TRIM(COALESCE(t.`linked_transaction`, '')) = '' THEN CAST(v_tx_id AS CHAR)
                        ELSE CONCAT(TRIM(t.`linked_transaction`), '; ', v_tx_id)
                    END,
                    'move', t.where_from, t.where_to, v_part_def, 0, 'В ожидании',
                    t.Project, t.Target_assembly, t.Supplied_component_number, t.Component_revision, t.Component_name,
                    t.Quantity_in_target_assembly, t.Quantity_of_target_assemblies, t.Components_quantity_in_assembly, t.Component_type,
                    t.For_supplied_as_assembly_components_provided_by_supplier, t.Part_material, t.Producer, t.Catalogue_number,
                    t.Producer_article, t.Distributer, t.Distributer_article, t.MBOM_type, t.Mass_kg, t.Unit_of_measure,
                    t.Height, t.Width, t.Length, t.Advanced_group, t.Address,
                    t.Document_no, t.Zakaz_no, t.Date_needed, t.Date_expected, t.Cost_total_rub,
                    t.Supplier, t.Location, t.Source, t.Initial_doc_no,
                    NULL, NULL, t.Order_prod, t.Order_OTK,
                    'Дефицит закупки'
                FROM `Transactions` t
                WHERE t.id = v_tx_id;
            END IF;
        END LOOP;

        CLOSE cur;

        INSERT INTO tmp_deficit_accum (erp_id, advanced_group, qty, src_tag)
        SELECT
            t.ERP_ID,
            t.Advanced_group,
            GREATEST(COALESCE(t.Quantity_of_parts_total, 0), COALESCE(t.Quantity_change, 0)) AS qty,
            CASE
              WHEN t.Source = 'Собственное производство' THEN 'Собственное производство'
              WHEN t.Source IS NULL OR TRIM(COALESCE(t.Source, '')) = '' THEN '__SRC_NULL__'
              ELSE 'Покупное'
            END AS src_tag
        FROM `Transactions` t
        WHERE t.type = 'move'
          AND t.where_to IN ('брак', 'отгрузка', 'изделие')
          AND t.Status_transaction = 'В ожидании'
          AND t.Status_warehouse = 'Дефицит закупки'
          AND GREATEST(COALESCE(t.Quantity_of_parts_total, 0), COALESCE(t.Quantity_change, 0)) > 0;

        INSERT INTO `Transactions` (
            ERP_ID, created_at, updated_at, created_by, updated_by, type, where_from, where_to,
            Quantity_of_parts_total, Quantity_change, Status_transaction,
            Project, Target_assembly, Supplied_component_number, Component_revision, Component_name,
            Quantity_in_target_assembly, Quantity_of_target_assemblies, Components_quantity_in_assembly,
            Component_type, For_supplied_as_assembly_components_provided_by_supplier, Part_material,
            Producer, Catalogue_number, Producer_article, Distributer, Distributer_article,
            MBOM_type, Mass_kg, Unit_of_measure, Height, Width, Length,
            Advanced_group, Address,
            Document_no, Zakaz_no, Date_needed, Date_expected, Cost_total_rub,
            Supplier, Location, Source, Initial_doc_no,
            Order_purch, Order_wh, Order_prod, Order_OTK, Status_warehouse
        )
        SELECT
            d.erp_id, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 'deficit', 'deficit',
            'change', 'внешний', 'склад',
            0, (d.need_qty - COALESCE(o.covered_change_qty, 0)), 'В ожидании',
            tmpl.`Project`, tmpl.`Target_assembly`, tmpl.`Supplied_component_number`, tmpl.`Component_revision`, tmpl.`Component_name`,
            tmpl.`Quantity_in_target_assembly`, tmpl.`Quantity_of_target_assemblies`,
            COALESCE(
                tmpl.`Components_quantity_in_assembly`,
                (SELECT mm.`Components_quantity_in_assembly` FROM `Main` mm WHERE mm.`ERP_ID` = d.`erp_id` LIMIT 1),
                (SELECT COALESCE(MAX(t2.`Components_quantity_in_assembly`), 0) FROM `Transactions` t2 WHERE t2.`ERP_ID` = d.`erp_id`),
                0
            ),
            tmpl.`Component_type`, tmpl.`For_supplied_as_assembly_components_provided_by_supplier`, tmpl.`Part_material`,
            tmpl.`Producer`, tmpl.`Catalogue_number`, tmpl.`Producer_article`, tmpl.`Distributer`, tmpl.`Distributer_article`,
            tmpl.`MBOM_type`, tmpl.`Mass_kg`, tmpl.`Unit_of_measure`, tmpl.`Height`, tmpl.`Width`, tmpl.`Length`,
            d.`advanced_group`, tmpl.`Address`,
            tmpl.`Document_no`, tmpl.`Zakaz_no`, tmpl.`Date_needed`, tmpl.`Date_expected`, tmpl.`Cost_total_rub`,
            tmpl.`Supplier`, tmpl.`Location`,
            CASE d.`src_tag`
              WHEN 'Собственное производство' THEN 'Собственное производство'
              WHEN '__SRC_NULL__' THEN NULL
              ELSE 'Покупное'
            END,
            tmpl.`Initial_doc_no`,
            CASE d.`src_tag`
              WHEN 'Собственное производство' THEN 'Собственное производство'
              ELSE 'Ожидание закупки'
            END,
            NULL,
            CASE d.`src_tag`
              WHEN 'Собственное производство' THEN 'Принято в изготовление'
              ELSE NULL
            END,
            tmpl.`Order_OTK`,
            CASE d.`src_tag`
              WHEN 'Собственное производство' THEN 'Новая'
              ELSE 'Дефицит закупки'
            END
        FROM (
            SELECT `erp_id`, `advanced_group`, `src_tag`, SUM(`qty`) AS `need_qty`
            FROM tmp_deficit_accum
            GROUP BY `erp_id`, `advanced_group`, `src_tag`
        ) d
        LEFT JOIN (
            SELECT
                t.`ERP_ID` AS `erp_id`,
                t.`Advanced_group` AS `advanced_group`,
                CASE
                  WHEN t.`Source` = 'Собственное производство' THEN 'Собственное производство'
                  WHEN t.`Source` IS NULL OR TRIM(COALESCE(t.`Source`, '')) = '' THEN '__SRC_NULL__'
                  ELSE 'Покупное'
                END AS `src_match`,
                SUM(GREATEST(COALESCE(t.`Quantity_change`, 0), 0)) AS `covered_change_qty`
            FROM `Transactions` t
            WHERE t.`type` = 'change'
              AND t.`where_from` = 'внешний'
              AND t.`where_to` = 'склад'
              AND COALESCE(t.`Status_transaction`, '') NOT IN ('Отменено', 'Заменено')
            GROUP BY
                t.`ERP_ID`,
                t.`Advanced_group`,
                CASE
                  WHEN t.`Source` = 'Собственное производство' THEN 'Собственное производство'
                  WHEN t.`Source` IS NULL OR TRIM(COALESCE(t.`Source`, '')) = '' THEN '__SRC_NULL__'
                  ELSE 'Покупное'
                END
        ) o
          ON o.`erp_id` = d.`erp_id`
         AND ((o.`advanced_group` = d.`advanced_group`) OR (o.`advanced_group` IS NULL AND d.`advanced_group` IS NULL))
         AND o.`src_match` = d.`src_tag`
        INNER JOIN (
            SELECT
                t3.`ERP_ID` AS `ERP_ID`,
                t3.`Advanced_group` AS `Advanced_group`,
                CASE
                  WHEN t3.`Source` = 'Собственное производство' THEN 'Собственное производство'
                  WHEN t3.`Source` IS NULL OR TRIM(COALESCE(t3.`Source`, '')) = '' THEN '__SRC_NULL__'
                  ELSE 'Покупное'
                END AS `src_match`,
                MIN(t3.`Project`) AS `Project`,
                MIN(t3.`Target_assembly`) AS `Target_assembly`,
                MIN(t3.`Supplied_component_number`) AS `Supplied_component_number`,
                MIN(t3.`Component_revision`) AS `Component_revision`,
                MIN(t3.`Component_name`) AS `Component_name`,
                MIN(t3.`Quantity_in_target_assembly`) AS `Quantity_in_target_assembly`,
                MIN(t3.`Quantity_of_target_assemblies`) AS `Quantity_of_target_assemblies`,
                MIN(t3.`Components_quantity_in_assembly`) AS `Components_quantity_in_assembly`,
                MIN(t3.`Component_type`) AS `Component_type`,
                MIN(t3.`For_supplied_as_assembly_components_provided_by_supplier`) AS `For_supplied_as_assembly_components_provided_by_supplier`,
                MIN(t3.`Part_material`) AS `Part_material`,
                MIN(t3.`Producer`) AS `Producer`,
                MIN(t3.`Catalogue_number`) AS `Catalogue_number`,
                MIN(t3.`Producer_article`) AS `Producer_article`,
                MIN(t3.`Distributer`) AS `Distributer`,
                MIN(t3.`Distributer_article`) AS `Distributer_article`,
                MIN(t3.`MBOM_type`) AS `MBOM_type`,
                MIN(t3.`Mass_kg`) AS `Mass_kg`,
                MIN(t3.`Unit_of_measure`) AS `Unit_of_measure`,
                MIN(t3.`Height`) AS `Height`,
                MIN(t3.`Width`) AS `Width`,
                MIN(t3.`Length`) AS `Length`,
                MIN(t3.`Address`) AS `Address`,
                MIN(t3.`Document_no`) AS `Document_no`,
                MIN(t3.`Zakaz_no`) AS `Zakaz_no`,
                MIN(t3.`Date_needed`) AS `Date_needed`,
                MIN(t3.`Date_expected`) AS `Date_expected`,
                MIN(t3.`Cost_total_rub`) AS `Cost_total_rub`,
                MIN(t3.`Supplier`) AS `Supplier`,
                MIN(t3.`Location`) AS `Location`,
                MIN(t3.`Initial_doc_no`) AS `Initial_doc_no`,
                MIN(t3.`Order_OTK`) AS `Order_OTK`
            FROM `Transactions` t3
            WHERE t3.`type` = 'move'
              AND t3.`where_to` IN ('брак', 'отгрузка', 'изделие')
              AND t3.`Status_transaction` = 'В ожидании'
              AND t3.`Status_warehouse` = 'Дефицит закупки'
              AND GREATEST(COALESCE(t3.`Quantity_of_parts_total`, 0), COALESCE(t3.`Quantity_change`, 0)) > 0
            GROUP BY
                t3.`ERP_ID`,
                t3.`Advanced_group`,
                CASE
                  WHEN t3.`Source` = 'Собственное производство' THEN 'Собственное производство'
                  WHEN t3.`Source` IS NULL OR TRIM(COALESCE(t3.`Source`, '')) = '' THEN '__SRC_NULL__'
                  ELSE 'Покупное'
                END
        ) tmpl
          ON tmpl.`ERP_ID` = d.`erp_id`
         AND (tmpl.`Advanced_group` <=> d.`advanced_group`)
         AND tmpl.`src_match` = d.`src_tag`
        WHERE (d.`need_qty` - COALESCE(o.`covered_change_qty`, 0)) > 0;

        DROP TEMPORARY TABLE IF EXISTS tmp_deficit_accum;

        COMMIT;
        DO RELEASE_LOCK('lock_process_move_deficit_wh_to_shop');
    END IF;
END$$

DELIMITER ;
