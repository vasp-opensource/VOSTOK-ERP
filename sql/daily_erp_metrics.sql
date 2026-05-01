-- collect_erp_metrics: ежедневные агрегаты (performance_log, Import, Transactions, Main) в erp_metrics.
-- Суммы по Main включают Quantity_of_rework (миграция: alter_erp_metrics_Quantity_of_rework.sql).
-- phpMyAdmin: выполните весь скрипт целиком (вкладка SQL).

DELIMITER $$

DROP PROCEDURE IF EXISTS collect_erp_metrics$$

CREATE PROCEDURE collect_erp_metrics()
BEGIN
    DECLARE v_period_end DATETIME(6);
    DECLARE v_period_start DATETIME(6);
    DECLARE v_period_date DATE;

    DECLARE v_cycletime_avg DECIMAL(16,3) DEFAULT 0;
    DECLARE v_cycletime_max DECIMAL(16,3) DEFAULT 0;
    DECLARE v_imported_rows BIGINT DEFAULT 0;
    DECLARE v_transactions_count BIGINT DEFAULT 0;

    DECLARE v_curr_expect_supply BIGINT DEFAULT 0;
    DECLARE v_curr_inProcess_purchase BIGINT DEFAULT 0;
    DECLARE v_curr_inProcess_manufacturing BIGINT DEFAULT 0;
    DECLARE v_curr_Quantity_in_warehouse BIGINT DEFAULT 0;
    DECLARE v_curr_Quantity_in_kitting BIGINT DEFAULT 0;
    DECLARE v_curr_Quantity_on_shopfloor BIGINT DEFAULT 0;
    DECLARE v_curr_Quantity_implemented BIGINT DEFAULT 0;
    DECLARE v_curr_Quantity_shipped BIGINT DEFAULT 0;
    DECLARE v_curr_Quantity_of_losses BIGINT DEFAULT 0;
    DECLARE v_curr_Quantity_of_rework BIGINT DEFAULT 0;

    DECLARE v_prev_expect_supply BIGINT DEFAULT 0;
    DECLARE v_prev_inProcess_purchase BIGINT DEFAULT 0;
    DECLARE v_prev_inProcess_manufacturing BIGINT DEFAULT 0;
    DECLARE v_prev_Quantity_in_warehouse BIGINT DEFAULT 0;
    DECLARE v_prev_Quantity_in_kitting BIGINT DEFAULT 0;
    DECLARE v_prev_Quantity_on_shopfloor BIGINT DEFAULT 0;
    DECLARE v_prev_Quantity_implemented BIGINT DEFAULT 0;
    DECLARE v_prev_Quantity_shipped BIGINT DEFAULT 0;
    DECLARE v_prev_Quantity_of_losses BIGINT DEFAULT 0;
    DECLARE v_prev_Quantity_of_rework BIGINT DEFAULT 0;

    SET v_period_end = NOW(6);
    SET v_period_start = v_period_end - INTERVAL 1 DAY;
    SET v_period_date = DATE(v_period_end);

    /* Время выполнения батча за прошедшие сутки */
    SELECT
        COALESCE(AVG(pl.duration_ms), 0),
        COALESCE(MAX(pl.duration_ms), 0)
    INTO
        v_cycletime_avg,
        v_cycletime_max
    FROM performance_log pl
    WHERE pl.batch_name = 'run_erp_scheduled_batch'
      AND pl.procedure_name = '__batch_total__'
      AND pl.status = 'OK'
      AND pl.created_at >= v_period_start
      AND pl.created_at < v_period_end;

    /* Количество импортированных записей за период */
    SELECT COALESCE(COUNT(*), 0)
    INTO v_imported_rows
    FROM `Import` i
    WHERE i.Status_import = 'Импортировано'
      AND i.updated_at >= v_period_start
      AND i.updated_at < v_period_end;

    /* Количество новых транзакций за период */
    SELECT COALESCE(COUNT(*), 0)
    INTO v_transactions_count
    FROM `Transactions` t
    WHERE t.created_at >= v_period_start
      AND t.created_at < v_period_end;

    /* Текущие суммарные снимки */
    SELECT COALESCE(SUM(COALESCE(t.Quantity_change, 0)), 0)
    INTO v_curr_expect_supply
    FROM `Transactions` t
    WHERE t.type = 'change'
      AND t.where_from = 'внешний'
      AND t.where_to = 'склад'
      AND t.Status_transaction = 'В ожидании'
      AND t.Status_warehouse = 'Новая';

    SELECT
        COALESCE(SUM(COALESCE(m.inProcess_purchase, 0)), 0),
        COALESCE(SUM(COALESCE(m.inProcess_manufacturing, 0)), 0),
        COALESCE(SUM(COALESCE(m.Quantity_in_warehouse, 0)), 0),
        COALESCE(SUM(COALESCE(m.Quantity_in_kitting, 0)), 0),
        COALESCE(SUM(COALESCE(m.Quantity_on_shopfloor, 0)), 0),
        COALESCE(SUM(COALESCE(m.Quantity_implemented, 0)), 0),
        COALESCE(SUM(COALESCE(m.Quantity_shipped, 0)), 0),
        COALESCE(SUM(COALESCE(m.Quantity_of_losses, 0)), 0),
        COALESCE(SUM(COALESCE(m.Quantity_of_rework, 0)), 0)
    INTO
        v_curr_inProcess_purchase,
        v_curr_inProcess_manufacturing,
        v_curr_Quantity_in_warehouse,
        v_curr_Quantity_in_kitting,
        v_curr_Quantity_on_shopfloor,
        v_curr_Quantity_implemented,
        v_curr_Quantity_shipped,
        v_curr_Quantity_of_losses,
        v_curr_Quantity_of_rework
    FROM `Main` m;

    /* Снимки прошлого периода (последняя сохраненная запись) */
    SELECT
        COALESCE(d.snapshot_expect_supply, 0),
        COALESCE(d.snapshot_inProcess_purchase, 0),
        COALESCE(d.snapshot_inProcess_manufacturing, 0),
        COALESCE(d.snapshot_Quantity_in_warehouse, 0),
        COALESCE(d.snapshot_Quantity_in_kitting, 0),
        COALESCE(d.snapshot_Quantity_on_shopfloor, 0),
        COALESCE(d.snapshot_Quantity_implemented, 0),
        COALESCE(d.snapshot_Quantity_shipped, 0),
        COALESCE(d.snapshot_Quantity_of_losses, 0),
        COALESCE(d.snapshot_Quantity_of_rework, 0)
    INTO
        v_prev_expect_supply,
        v_prev_inProcess_purchase,
        v_prev_inProcess_manufacturing,
        v_prev_Quantity_in_warehouse,
        v_prev_Quantity_in_kitting,
        v_prev_Quantity_on_shopfloor,
        v_prev_Quantity_implemented,
        v_prev_Quantity_shipped,
        v_prev_Quantity_of_losses,
        v_prev_Quantity_of_rework
    FROM erp_metrics d
    WHERE d.period_date < v_period_date
    ORDER BY d.period_date DESC
    LIMIT 1;

    INSERT INTO erp_metrics (
        period_start,
        period_end,
        period_date,
        cycletime_avg,
        cycletime_max,
        imported_rows,
        transactions_count,
        Quantity_transanctions_change,
        Quantity_inPurchase_change,
        Quantity_inManufacturing_change,
        Quantity_in_warehouse_change,
        Quantity_in_kitting_change,
        Quantity_on_shopfloor_change,
        Quantity_implemented_change,
        Quantity_shipped_change,
        Quantity_of_losses_change,
        Quantity_of_rework_change,
        snapshot_expect_supply,
        snapshot_inProcess_purchase,
        snapshot_inProcess_manufacturing,
        snapshot_Quantity_in_warehouse,
        snapshot_Quantity_in_kitting,
        snapshot_Quantity_on_shopfloor,
        snapshot_Quantity_implemented,
        snapshot_Quantity_shipped,
        snapshot_Quantity_of_losses,
        snapshot_Quantity_of_rework
    )
    VALUES (
        v_period_start,
        v_period_end,
        v_period_date,
        v_cycletime_avg,
        v_cycletime_max,
        v_imported_rows,
        v_transactions_count,
        v_curr_expect_supply - v_prev_expect_supply,
        v_curr_inProcess_purchase - v_prev_inProcess_purchase,
        v_curr_inProcess_manufacturing - v_prev_inProcess_manufacturing,
        v_curr_Quantity_in_warehouse - v_prev_Quantity_in_warehouse,
        v_curr_Quantity_in_kitting - v_prev_Quantity_in_kitting,
        v_curr_Quantity_on_shopfloor - v_prev_Quantity_on_shopfloor,
        v_curr_Quantity_implemented - v_prev_Quantity_implemented,
        v_curr_Quantity_shipped - v_prev_Quantity_shipped,
        v_curr_Quantity_of_losses - v_prev_Quantity_of_losses,
        v_curr_Quantity_of_rework - v_prev_Quantity_of_rework,
        v_curr_expect_supply,
        v_curr_inProcess_purchase,
        v_curr_inProcess_manufacturing,
        v_curr_Quantity_in_warehouse,
        v_curr_Quantity_in_kitting,
        v_curr_Quantity_on_shopfloor,
        v_curr_Quantity_implemented,
        v_curr_Quantity_shipped,
        v_curr_Quantity_of_losses,
        v_curr_Quantity_of_rework
    )
    ON DUPLICATE KEY UPDATE
        period_start = VALUES(period_start),
        period_end = VALUES(period_end),
        cycletime_avg = VALUES(cycletime_avg),
        cycletime_max = VALUES(cycletime_max),
        imported_rows = VALUES(imported_rows),
        transactions_count = VALUES(transactions_count),
        Quantity_transanctions_change = VALUES(Quantity_transanctions_change),
        Quantity_inPurchase_change = VALUES(Quantity_inPurchase_change),
        Quantity_inManufacturing_change = VALUES(Quantity_inManufacturing_change),
        Quantity_in_warehouse_change = VALUES(Quantity_in_warehouse_change),
        Quantity_in_kitting_change = VALUES(Quantity_in_kitting_change),
        Quantity_on_shopfloor_change = VALUES(Quantity_on_shopfloor_change),
        Quantity_implemented_change = VALUES(Quantity_implemented_change),
        Quantity_shipped_change = VALUES(Quantity_shipped_change),
        Quantity_of_losses_change = VALUES(Quantity_of_losses_change),
        Quantity_of_rework_change = VALUES(Quantity_of_rework_change),
        snapshot_expect_supply = VALUES(snapshot_expect_supply),
        snapshot_inProcess_purchase = VALUES(snapshot_inProcess_purchase),
        snapshot_inProcess_manufacturing = VALUES(snapshot_inProcess_manufacturing),
        snapshot_Quantity_in_warehouse = VALUES(snapshot_Quantity_in_warehouse),
        snapshot_Quantity_in_kitting = VALUES(snapshot_Quantity_in_kitting),
        snapshot_Quantity_on_shopfloor = VALUES(snapshot_Quantity_on_shopfloor),
        snapshot_Quantity_implemented = VALUES(snapshot_Quantity_implemented),
        snapshot_Quantity_shipped = VALUES(snapshot_Quantity_shipped),
        snapshot_Quantity_of_losses = VALUES(snapshot_Quantity_of_losses),
        snapshot_Quantity_of_rework = VALUES(snapshot_Quantity_of_rework);
END$$

DELIMITER ;
