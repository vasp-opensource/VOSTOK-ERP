-- Таблица erp_metrics: снимки и приросты по Main.Quantity_of_rework (ежедневный collect_erp_metrics).
-- Выполнить один раз на БД, где уже есть erp_metrics с колонками ...Quantity_of_losses...

ALTER TABLE `erp_metrics`
    ADD COLUMN `Quantity_of_rework_change` BIGINT NOT NULL DEFAULT 0
        AFTER `Quantity_of_losses_change`,
    ADD COLUMN `snapshot_Quantity_of_rework` BIGINT NOT NULL DEFAULT 0
        AFTER `snapshot_Quantity_of_losses`;
