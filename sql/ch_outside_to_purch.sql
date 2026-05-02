-- ch_outside_to_purch: передача change «внешний → склад» в закупку (Order_purch «В закупке»/«Оплачено» и Order_prod = «В закупку»).
-- Убедитесь, что значение «В закупку» есть в enum Order_prod в вашей БД.
--
-- Как ch_outside_to_ownProd: отбор в tmp_ch_outside_unite_ids, неттинг и Main — в ch_outside_unite (там новые реквизиты Transactions, Main.Quantity_of_rework по DEFAULT).
-- Блокировка и транзакция внутри ch_outside_unite.
--
-- #1137: во временной не дважды tmp в одном запросе; партнёр с тем же ERP_ID + Advanced_group (см. <=> ).

DELIMITER $$

DROP PROCEDURE IF EXISTS ch_outside_to_purch$$

CREATE PROCEDURE ch_outside_to_purch()
BEGIN
    DECLARE EXIT HANDLER FOR 3572, 1213, 1205
    BEGIN
        SET @erp_batch_blocked_message = 'Blocked: ch_outside_to_purch lock conflict';
        DROP TEMPORARY TABLE IF EXISTS tmp_ch_outside_erp_ids;
        DROP TEMPORARY TABLE IF EXISTS tmp_ch_outside_unite_partner_pick;
        DROP TEMPORARY TABLE IF EXISTS tmp_ch_outside_unite_snapshot;
        DROP TEMPORARY TABLE IF EXISTS tmp_ch_outside_unite_ids;
    END;

    DROP TEMPORARY TABLE IF EXISTS tmp_ch_outside_unite_ids;
    CREATE TEMPORARY TABLE tmp_ch_outside_unite_ids (
        id INT UNSIGNED PRIMARY KEY,
        ERP_ID VARCHAR(255) NOT NULL,
        Advanced_group TEXT NULL,
        Quantity_change BIGINT NOT NULL,
        is_incoming TINYINT(1) NOT NULL
    );

    /* Входящий батч: Новая / Дефицит закупки */
    INSERT INTO tmp_ch_outside_unite_ids (id, ERP_ID, Advanced_group, Quantity_change, is_incoming)
    SELECT
        t.id,
        t.ERP_ID,
        t.Advanced_group,
        COALESCE(t.Quantity_change, 0),
        1
    FROM `Transactions` t
    WHERE t.Status_warehouse IN ('Новая', 'Дефицит закупки')
      AND t.Status_transaction = 'В ожидании'
      AND t.Order_purch IN ('В закупке', 'Оплачено')
      AND (
          t.Order_prod = 'В закупку'
          OR t.Recommend_purchprod IN ('В закупку', 'Уточнить ревизию в закупке')
          OR (
              t.Recommend_purchprod = 'Уточнить кол-во в закупке'
              AND t.Order_purch = 'В закупке'
          )
      )
      AND t.type = 'change'
      AND t.where_from = 'внешний'
      AND t.where_to = 'склад';

    /* Уже в закупке, «В ожидании», та же пара ERP_ID + Advanced_group (#1137) */
    DROP TEMPORARY TABLE IF EXISTS tmp_ch_outside_unite_snapshot;
    CREATE TEMPORARY TABLE tmp_ch_outside_unite_snapshot AS
    SELECT id FROM tmp_ch_outside_unite_ids;

    DROP TEMPORARY TABLE IF EXISTS tmp_ch_outside_unite_partner_pick;
    CREATE TEMPORARY TABLE tmp_ch_outside_unite_partner_pick AS
    SELECT DISTINCT
        t.id,
        t.ERP_ID,
        t.Advanced_group,
        COALESCE(t.Quantity_change, 0) AS Quantity_change,
        0 AS is_incoming
    FROM tmp_ch_outside_unite_ids x
    INNER JOIN `Transactions` t
      ON t.`ERP_ID` = x.`ERP_ID`
     AND (t.`Advanced_group` <=> x.`Advanced_group`)
     AND t.`id` <> x.`id`
    LEFT JOIN tmp_ch_outside_unite_snapshot snap ON snap.id = t.id
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

    INSERT INTO tmp_ch_outside_unite_ids (id, ERP_ID, Advanced_group, Quantity_change, is_incoming)
    SELECT id, ERP_ID, Advanced_group, Quantity_change, is_incoming FROM tmp_ch_outside_unite_partner_pick;

    DROP TEMPORARY TABLE IF EXISTS tmp_ch_outside_unite_partner_pick;
    DROP TEMPORARY TABLE IF EXISTS tmp_ch_outside_unite_snapshot;

    /* Снимок ERP_ID до вызова unite (финальный update move) */
    DROP TEMPORARY TABLE IF EXISTS tmp_ch_outside_erp_ids;
    CREATE TEMPORARY TABLE tmp_ch_outside_erp_ids AS
    SELECT DISTINCT ERP_ID
    FROM tmp_ch_outside_unite_ids;

    CALL ch_outside_unite(
        'lock_process_purchase_change_to_main',
        'Покупное',
        'ch_outside_to_purch',
        'В закупке',
        'В закупке',
        'В закупке',
        0
    );

    /* Для ERP_ID из батча: move «Ожидание поставки» -> «Новая» (как ch_outside_to_ownProd) */
    UPDATE `Transactions` t
    INNER JOIN tmp_ch_outside_erp_ids e ON e.`ERP_ID` = t.`ERP_ID`
    SET
        t.`Status_warehouse` = 'Новая',
        t.`updated_at`       = NOW(),
        t.`updated_by`       = CASE
                                  WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'ch_outside_to_purch'
                                  ELSE CONCAT(t.`updated_by`, '; ', 'ch_outside_to_purch')
                               END
    WHERE t.`type` = 'move'
      AND t.`Status_transaction` = 'В ожидании'
      AND t.`Status_warehouse` = 'Ожидание поставки';

    DROP TEMPORARY TABLE IF EXISTS tmp_ch_outside_erp_ids;
END$$

DELIMITER ;
