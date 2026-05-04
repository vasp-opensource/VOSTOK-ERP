-- Синхронизация адреса хранения из Main в Transactions.
-- При заполнении/уточнении Main.cell_id поле Main.Address уже заполняется
-- триггером из Cells.address_code, после чего эти триггеры обновляют все
-- Transactions.Address с тем же ERP_ID.

DELIMITER //

DROP TRIGGER IF EXISTS `ai_main_sync_transactions_address`//
CREATE TRIGGER `ai_main_sync_transactions_address`
AFTER INSERT ON `Main`
FOR EACH ROW
BEGIN
    IF NEW.`cell_id` IS NOT NULL THEN
        UPDATE `Transactions`
           SET `Address` = NEW.`Address`
         WHERE `ERP_ID` COLLATE utf8mb4_unicode_ci = NEW.`ERP_ID` COLLATE utf8mb4_unicode_ci;
    END IF;
END//

DROP TRIGGER IF EXISTS `au_main_sync_transactions_address`//
CREATE TRIGGER `au_main_sync_transactions_address`
AFTER UPDATE ON `Main`
FOR EACH ROW
BEGIN
    IF NEW.`cell_id` IS NOT NULL
       AND (
           NOT (NEW.`cell_id` <=> OLD.`cell_id`)
           OR NOT (NEW.`Address` <=> OLD.`Address`)
           OR NOT (NEW.`ERP_ID` <=> OLD.`ERP_ID`)
       ) THEN
        UPDATE `Transactions`
           SET `Address` = NEW.`Address`
         WHERE `ERP_ID` COLLATE utf8mb4_unicode_ci = NEW.`ERP_ID` COLLATE utf8mb4_unicode_ci;
    END IF;
END//

DELIMITER ;
