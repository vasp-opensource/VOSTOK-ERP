-- ch_outside_to_ownProd: внешний → склад (собственное производство). Только отбор в tmp_ch_outside_unite_ids; объединение и Main — ch_outside_unite.
-- Критерии: Order_purch «Собственное производство», Order_prod «Принято в изготовление»; партнёр — «В изготовлении», «В ожидании» (не merge-строки процедуры).
-- Перед использованием выполните ch_outside_unite.sql (процедура ch_outside_unite).
-- Суммарные INSERT в Transactions и нулевой по умолчанию Main.Quantity_of_rework задаются в ch_outside_unite (см. колонки как в ch_merge_same_advGroup).

DELIMITER $$

DROP PROCEDURE IF EXISTS ch_outside_to_ownProd$$

CREATE PROCEDURE ch_outside_to_ownProd()
BEGIN
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
      AND t.Order_purch = 'Собственное производство'
      AND t.Order_prod = 'Принято в изготовление'
      AND t.type = 'change'
      AND t.where_from = 'внешний'
      AND t.where_to = 'склад';

    /* Уже «В изготовлении», «В ожидании», та же пара ERP_ID + Advanced_group (#1137) */
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
      AND t.`Order_purch` = 'Собственное производство'
      AND t.`Order_prod` = 'Принято в изготовление'
      AND t.`Status_warehouse` = 'В изготовлении'
      AND t.`Status_transaction` = 'В ожидании'
      AND COALESCE(t.`Quantity_change`, 0) <> 0
      AND snap.id IS NULL;

    INSERT INTO tmp_ch_outside_unite_ids (id, ERP_ID, Advanced_group, Quantity_change, is_incoming)
    SELECT id, ERP_ID, Advanced_group, Quantity_change, is_incoming FROM tmp_ch_outside_unite_partner_pick;

    DROP TEMPORARY TABLE IF EXISTS tmp_ch_outside_unite_partner_pick;
    DROP TEMPORARY TABLE IF EXISTS tmp_ch_outside_unite_snapshot;
    
    /* Снимок ERP_ID до вызова unite (используется в финальном update move) */
    DROP TEMPORARY TABLE IF EXISTS tmp_ch_outside_erp_ids;
    CREATE TEMPORARY TABLE tmp_ch_outside_erp_ids AS
    SELECT DISTINCT ERP_ID
    FROM tmp_ch_outside_unite_ids;

    CALL ch_outside_unite(
        'lock_process_ownprod_change_to_main',
        'Собственное производство',
        'ch_outside_to_ownProd',
        'В изготовлении',
        'В изготовлении',
        'В изготовлении',
        1
    );

    /* Для ERP_ID из обработанного батча: move "Ожидание поставки" -> "Новая" */
    UPDATE `Transactions` t
    INNER JOIN tmp_ch_outside_erp_ids e ON e.`ERP_ID` = t.`ERP_ID`
    SET
        t.`Status_warehouse` = 'Новая',
        t.`updated_at`       = NOW(),
        t.`updated_by`       = CASE
                                  WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'ch_outside_to_ownProd'
                                  ELSE CONCAT(t.`updated_by`, '; ', 'ch_outside_to_ownProd')
                               END
    WHERE t.`type` = 'move'
      AND t.`Status_transaction` = 'В ожидании'
      AND t.`Status_warehouse` = 'Ожидание поставки';

    DROP TEMPORARY TABLE IF EXISTS tmp_ch_outside_erp_ids;
END$$

DELIMITER ;
