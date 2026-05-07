-- Справочник адресного хранения: Склад -> Стеллаж -> Ячейка.
-- Один ERP_ID в Main ссылается на одну ячейку через Main.cell_id.
-- Main.Address оставлен как текстовый снимок адреса для совместимости с текущими процедурами.

CREATE TABLE IF NOT EXISTS `Warehouses` (
    `id` int unsigned NOT NULL AUTO_INCREMENT,
    `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    `warehouse_no` int unsigned NOT NULL COMMENT 'Номер склада для адреса W{warehouse_no}',
    `name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
    `comment` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_warehouses_warehouse_no` (`warehouse_no`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `Racks` (
    `id` int unsigned NOT NULL AUTO_INCREMENT,
    `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    `warehouse_id` int unsigned NOT NULL,
    `rack_no` int unsigned NOT NULL COMMENT 'Номер стеллажа для адреса R{rack_no}',
    `name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
    `comment` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_racks_warehouse_rack_no` (`warehouse_id`, `rack_no`),
    KEY `idx_racks_warehouse_id` (`warehouse_id`),
    CONSTRAINT `fk_racks_warehouse`
        FOREIGN KEY (`warehouse_id`) REFERENCES `Warehouses` (`id`)
        ON UPDATE CASCADE
        ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `Cells` (
    `id` int unsigned NOT NULL AUTO_INCREMENT,
    `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    `rack_id` int unsigned NOT NULL,
    `cell_no` int unsigned NOT NULL COMMENT 'Номер ячейки для адреса C{cell_no}',
    `address_code` varchar(64) CHARACTER SET ascii COLLATE ascii_general_ci NULL DEFAULT NULL
        COMMENT 'Заполняется триггером; NULL разрешён, чтобы NocoDB не требовал ручной ввод',
    `comment` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_cells_rack_cell_no` (`rack_id`, `cell_no`),
    UNIQUE KEY `uk_cells_address_code` (`address_code`),
    KEY `idx_cells_rack_id` (`rack_id`),
    CONSTRAINT `fk_cells_rack`
        FOREIGN KEY (`rack_id`) REFERENCES `Racks` (`id`)
        ON UPDATE CASCADE
        ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

SET @sql_add_main_cell_id = (
    SELECT IF(
        EXISTS (
            SELECT 1
            FROM information_schema.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME = 'Main'
              AND COLUMN_NAME = 'cell_id'
        ),
        'SELECT 1',
        'ALTER TABLE `Main` ADD COLUMN `cell_id` int unsigned NULL AFTER `Address`'
    )
);
PREPARE stmt_add_main_cell_id FROM @sql_add_main_cell_id;
EXECUTE stmt_add_main_cell_id;
DEALLOCATE PREPARE stmt_add_main_cell_id;

SET @sql_add_main_cell_idx = (
    SELECT IF(
        EXISTS (
            SELECT 1
            FROM information_schema.STATISTICS
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME = 'Main'
              AND INDEX_NAME = 'idx_main_cell_id'
        ),
        'SELECT 1',
        'ALTER TABLE `Main` ADD INDEX `idx_main_cell_id` (`cell_id`)'
    )
);
PREPARE stmt_add_main_cell_idx FROM @sql_add_main_cell_idx;
EXECUTE stmt_add_main_cell_idx;
DEALLOCATE PREPARE stmt_add_main_cell_idx;

SET @sql_add_main_cell_fk = (
    SELECT IF(
        EXISTS (
            SELECT 1
            FROM information_schema.TABLE_CONSTRAINTS
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME = 'Main'
              AND CONSTRAINT_NAME = 'fk_main_cell'
              AND CONSTRAINT_TYPE = 'FOREIGN KEY'
        ),
        'SELECT 1',
        'ALTER TABLE `Main` ADD CONSTRAINT `fk_main_cell` FOREIGN KEY (`cell_id`) REFERENCES `Cells` (`id`) ON UPDATE CASCADE ON DELETE SET NULL'
    )
);
PREPARE stmt_add_main_cell_fk FROM @sql_add_main_cell_fk;
EXECUTE stmt_add_main_cell_fk;
DEALLOCATE PREPARE stmt_add_main_cell_fk;

DELIMITER //

DROP TRIGGER IF EXISTS `bi_cells_address_code`//
CREATE TRIGGER `bi_cells_address_code`
BEFORE INSERT ON `Cells`
FOR EACH ROW
BEGIN
    DECLARE v_warehouse_no int unsigned;
    DECLARE v_rack_no int unsigned;

    SELECT w.`warehouse_no`, r.`rack_no`
      INTO v_warehouse_no, v_rack_no
      FROM `Racks` r
      JOIN `Warehouses` w ON w.`id` = r.`warehouse_id`
     WHERE r.`id` = NEW.`rack_id`;

    SET NEW.`address_code` = CONCAT('W', v_warehouse_no, 'R', v_rack_no, 'C', NEW.`cell_no`);
END//

DROP TRIGGER IF EXISTS `bu_cells_address_code`//
CREATE TRIGGER `bu_cells_address_code`
BEFORE UPDATE ON `Cells`
FOR EACH ROW
BEGIN
    DECLARE v_warehouse_no int unsigned;
    DECLARE v_rack_no int unsigned;

    SELECT w.`warehouse_no`, r.`rack_no`
      INTO v_warehouse_no, v_rack_no
      FROM `Racks` r
      JOIN `Warehouses` w ON w.`id` = r.`warehouse_id`
     WHERE r.`id` = NEW.`rack_id`;

    SET NEW.`address_code` = CONCAT('W', v_warehouse_no, 'R', v_rack_no, 'C', NEW.`cell_no`);
END//

DROP TRIGGER IF EXISTS `au_cells_sync_main_address`//
CREATE TRIGGER `au_cells_sync_main_address`
AFTER UPDATE ON `Cells`
FOR EACH ROW
BEGIN
    IF NEW.`address_code` <> OLD.`address_code` THEN
        UPDATE `Main`
           SET `Address` = NEW.`address_code`
         WHERE `cell_id` = NEW.`id`;
    END IF;
END//

DROP TRIGGER IF EXISTS `au_racks_refresh_cell_addresses`//
CREATE TRIGGER `au_racks_refresh_cell_addresses`
AFTER UPDATE ON `Racks`
FOR EACH ROW
BEGIN
    IF NEW.`warehouse_id` <> OLD.`warehouse_id` OR NEW.`rack_no` <> OLD.`rack_no` THEN
        UPDATE `Cells`
           SET `address_code` = `address_code`
         WHERE `rack_id` = NEW.`id`;
    END IF;
END//

DROP TRIGGER IF EXISTS `au_warehouses_refresh_cell_addresses`//
CREATE TRIGGER `au_warehouses_refresh_cell_addresses`
AFTER UPDATE ON `Warehouses`
FOR EACH ROW
BEGIN
    IF NEW.`warehouse_no` <> OLD.`warehouse_no` THEN
        UPDATE `Cells` c
        JOIN `Racks` r ON r.`id` = c.`rack_id`
           SET c.`address_code` = c.`address_code`
         WHERE r.`warehouse_id` = NEW.`id`;
    END IF;
END//

DROP TRIGGER IF EXISTS `au_warehouses_sync_transactions_location`//
CREATE TRIGGER `au_warehouses_sync_transactions_location`
AFTER UPDATE ON `Warehouses`
FOR EACH ROW
BEGIN
    DECLARE v_old_location TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
    DECLARE v_new_location TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
    DECLARE CONTINUE HANDLER FOR 1205, 1213, 3572 BEGIN END;

    IF NOT (NEW.`name` <=> OLD.`name`)
       OR NOT (NEW.`comment` <=> OLD.`comment`) THEN
        SET v_old_location = NULLIF(
            TRIM(
                CONCAT(
                    COALESCE(NULLIF(TRIM(COALESCE(OLD.`name`, '')), ''), ''),
                    CASE
                        WHEN NULLIF(TRIM(COALESCE(OLD.`comment`, '')), '') IS NULL THEN ''
                        ELSE CONCAT(' - ', TRIM(COALESCE(OLD.`comment`, '')))
                    END
                )
            ),
            ''
        );

        SET v_new_location = NULLIF(
            TRIM(
                CONCAT(
                    COALESCE(NULLIF(TRIM(COALESCE(NEW.`name`, '')), ''), ''),
                    CASE
                        WHEN NULLIF(TRIM(COALESCE(NEW.`comment`, '')), '') IS NULL THEN ''
                        ELSE CONCAT(' - ', TRIM(COALESCE(NEW.`comment`, '')))
                    END
                )
            ),
            ''
        );

        -- 1) Базовая синхронизация по текущей связке Main.cell_id -> Cells -> Racks -> Warehouses.
        UPDATE `Transactions` t
        JOIN `Main` m
          ON m.`ERP_ID` COLLATE utf8mb4_unicode_ci = t.`ERP_ID` COLLATE utf8mb4_unicode_ci
        JOIN `Cells` c
          ON c.`id` = m.`cell_id`
        JOIN `Racks` r
          ON r.`id` = c.`rack_id`
         SET t.`Location` = v_new_location,
             t.`updated_by` = CASE
                WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'au_warehouses_sync_transactions_location'
                ELSE CONCAT(t.`updated_by`, '; ', 'au_warehouses_sync_transactions_location')
             END,
             t.`updated_at` = CURRENT_TIMESTAMP
       WHERE r.`warehouse_id` = NEW.`id`
         AND m.`cell_id` IS NOT NULL
         AND NOT (
             CONVERT(TRIM(COALESCE(t.`Location`, '')) USING utf8mb4) COLLATE utf8mb4_unicode_ci
             <=> CONVERT(TRIM(COALESCE(v_new_location, '')) USING utf8mb4) COLLATE utf8mb4_unicode_ci
         );

        -- 2) Fallback для move: обновить строки, где Location хранит старый текст склада,
        -- даже если текущая связка через Main.cell_id отсутствует/изменилась.
        UPDATE `Transactions` t
           SET t.`Location` = v_new_location,
               t.`updated_by` = CASE
                   WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'au_warehouses_sync_transactions_location'
                   ELSE CONCAT(t.`updated_by`, '; ', 'au_warehouses_sync_transactions_location')
               END,
               t.`updated_at` = CURRENT_TIMESTAMP
         WHERE t.`type` = 'move'
           AND CONVERT(TRIM(COALESCE(t.`Location`, '')) USING utf8mb4) COLLATE utf8mb4_unicode_ci
               <=> CONVERT(TRIM(COALESCE(v_old_location, '')) USING utf8mb4) COLLATE utf8mb4_unicode_ci
           AND NOT (
               CONVERT(TRIM(COALESCE(t.`Location`, '')) USING utf8mb4) COLLATE utf8mb4_unicode_ci
               <=> CONVERT(TRIM(COALESCE(v_new_location, '')) USING utf8mb4) COLLATE utf8mb4_unicode_ci
           );
    END IF;
END//

DROP TRIGGER IF EXISTS `bi_main_sync_address_from_cell`//
CREATE TRIGGER `bi_main_sync_address_from_cell`
BEFORE INSERT ON `Main`
FOR EACH ROW
BEGIN
    DECLARE v_address_code varchar(64);

    IF NEW.`cell_id` IS NOT NULL THEN
        SELECT c.`address_code`
          INTO v_address_code
          FROM `Cells` c
         WHERE c.`id` = NEW.`cell_id`;

        SET NEW.`Address` = v_address_code;
    END IF;
END//

DROP TRIGGER IF EXISTS `bu_main_sync_address_from_cell`//
CREATE TRIGGER `bu_main_sync_address_from_cell`
BEFORE UPDATE ON `Main`
FOR EACH ROW
BEGIN
    DECLARE v_address_code varchar(64);

    IF NEW.`cell_id` IS NOT NULL THEN
        SELECT c.`address_code`
          INTO v_address_code
          FROM `Cells` c
         WHERE c.`id` = NEW.`cell_id`;

        SET NEW.`Address` = v_address_code;
    END IF;
END//

DROP TRIGGER IF EXISTS `ai_main_sync_transactions_address`//
CREATE TRIGGER `ai_main_sync_transactions_address`
AFTER INSERT ON `Main`
FOR EACH ROW
BEGIN
    DECLARE v_location_text TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

    IF NEW.`cell_id` IS NOT NULL THEN
        SELECT NULLIF(
                   TRIM(
                       CONCAT(
                           COALESCE(NULLIF(TRIM(COALESCE(w.`name`, '')), ''), ''),
                           CASE
                               WHEN NULLIF(TRIM(COALESCE(w.`comment`, '')), '') IS NULL THEN ''
                               ELSE CONCAT(' - ', TRIM(COALESCE(w.`comment`, '')))
                           END
                       )
                   ),
                   ''
               )
          INTO v_location_text
          FROM `Cells` c
          JOIN `Racks` r ON r.`id` = c.`rack_id`
          JOIN `Warehouses` w ON w.`id` = r.`warehouse_id`
         WHERE c.`id` = NEW.`cell_id`
         LIMIT 1;

        UPDATE `Transactions`
           SET `Address` = NEW.`Address`,
               `Location` = v_location_text
         WHERE `ERP_ID` COLLATE utf8mb4_unicode_ci = NEW.`ERP_ID` COLLATE utf8mb4_unicode_ci;
    END IF;
END//

DROP TRIGGER IF EXISTS `au_main_sync_transactions_address`//
CREATE TRIGGER `au_main_sync_transactions_address`
AFTER UPDATE ON `Main`
FOR EACH ROW
BEGIN
    DECLARE v_location_text TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

    IF NEW.`cell_id` IS NOT NULL
       AND (
           NOT (NEW.`cell_id` <=> OLD.`cell_id`)
           OR NOT (NEW.`Address` <=> OLD.`Address`)
           OR NOT (NEW.`ERP_ID` <=> OLD.`ERP_ID`)
       ) THEN
        SELECT NULLIF(
                   TRIM(
                       CONCAT(
                           COALESCE(NULLIF(TRIM(COALESCE(w.`name`, '')), ''), ''),
                           CASE
                               WHEN NULLIF(TRIM(COALESCE(w.`comment`, '')), '') IS NULL THEN ''
                               ELSE CONCAT(' - ', TRIM(COALESCE(w.`comment`, '')))
                           END
                       )
                   ),
                   ''
               )
          INTO v_location_text
          FROM `Cells` c
          JOIN `Racks` r ON r.`id` = c.`rack_id`
          JOIN `Warehouses` w ON w.`id` = r.`warehouse_id`
         WHERE c.`id` = NEW.`cell_id`
         LIMIT 1;

        UPDATE `Transactions`
           SET `Address` = NEW.`Address`,
               `Location` = v_location_text
         WHERE `ERP_ID` COLLATE utf8mb4_unicode_ci = NEW.`ERP_ID` COLLATE utf8mb4_unicode_ci;
    END IF;
END//

DELIMITER ;
