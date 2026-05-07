-- prework_location: назначает Main.cell_id по умолчанию для строк с пустым Transactions.Location.
-- Отбор выполняется по Transactions; если связанной записи в Main нет, строка пропускается.
-- Ячейка по умолчанию берется из location_rules.default_address с учетом project (ANY / ANY BUT / CSV),
-- затем выбирается правило с минимальным priority/id.

DROP PROCEDURE IF EXISTS prework_location;

DELIMITER $$

CREATE PROCEDURE prework_location()
BEGIN
    DECLARE v_lock_ok INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        IF v_lock_ok = 1 THEN
            DO RELEASE_LOCK('lock_prework_location');
        END IF;
        RESIGNAL;
    END;

    SELECT GET_LOCK('lock_prework_location', 0) INTO v_lock_ok;

    IF COALESCE(v_lock_ok, 0) <> 1 THEN
        SET @erp_batch_blocked_message = 'Blocked: lock_prework_location lock is already held';
    ELSE
        DROP TEMPORARY TABLE IF EXISTS `tmp_prework_location_candidates`;
        CREATE TEMPORARY TABLE `tmp_prework_location_candidates` (
            `main_id` INT UNSIGNED NOT NULL PRIMARY KEY,
            `project_value` VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL
        ) ENGINE=MEMORY;

        INSERT IGNORE INTO `tmp_prework_location_candidates` (`main_id`, `project_value`)
        SELECT DISTINCT
            m0.`id` AS main_id,
            CAST(t.`Project` AS CHAR CHARACTER SET utf8mb4) COLLATE utf8mb4_unicode_ci AS project_value
        FROM `Transactions` t
        INNER JOIN `Main` m0
          ON m0.`ERP_ID` COLLATE utf8mb4_unicode_ci = t.`ERP_ID` COLLATE utf8mb4_unicode_ci
        WHERE t.`ERP_ID` IS NOT NULL
          AND t.`Status_transaction` = 'В ожидании'
          AND (t.`Location` IS NULL OR TRIM(COALESCE(t.`Location`, '')) = '')
          AND m0.`cell_id` IS NULL;

        DROP TEMPORARY TABLE IF EXISTS `tmp_prework_location_selected`;
        CREATE TEMPORARY TABLE `tmp_prework_location_selected` AS
        SELECT
            q.`main_id`,
            q.`default_address`
        FROM (
            SELECT
                c.`main_id`,
                lr.`default_address`,
                ROW_NUMBER() OVER (
                    PARTITION BY c.`main_id`
                    ORDER BY lr.`priority`, lr.`id`
                ) AS rn
            FROM `tmp_prework_location_candidates` c
            INNER JOIN `location_rules` lr
              ON lr.`default_address` IS NOT NULL
             AND (
                    TRIM(CAST(lr.`project` AS CHAR CHARACTER SET utf8mb4)) COLLATE utf8mb4_unicode_ci = 'ANY' COLLATE utf8mb4_unicode_ci
                    OR (
                        UPPER(TRIM(CAST(lr.`project` AS CHAR CHARACTER SET utf8mb4))) COLLATE utf8mb4_unicode_ci
                            LIKE 'ANY BUT %' COLLATE utf8mb4_unicode_ci
                        AND FIND_IN_SET(
                            TRIM(COALESCE(CAST(c.`project_value` AS CHAR CHARACTER SET utf8mb4), '')) COLLATE utf8mb4_unicode_ci,
                            REPLACE(
                                TRIM(SUBSTRING(TRIM(CAST(lr.`project` AS CHAR CHARACTER SET utf8mb4)), 8)),
                                ', ',
                                ','
                            ) COLLATE utf8mb4_unicode_ci
                        ) = 0
                    )
                    OR FIND_IN_SET(
                        TRIM(COALESCE(CAST(c.`project_value` AS CHAR CHARACTER SET utf8mb4), '')) COLLATE utf8mb4_unicode_ci,
                        REPLACE(CAST(lr.`project` AS CHAR CHARACTER SET utf8mb4), ', ', ',') COLLATE utf8mb4_unicode_ci
                    ) > 0
                 )
        ) q
        WHERE q.rn = 1;
        ALTER TABLE `tmp_prework_location_selected`
          ADD PRIMARY KEY (`main_id`);

        UPDATE `Main` m
        INNER JOIN `tmp_prework_location_selected` s
          ON s.`main_id` = m.`id`
        SET
            m.`cell_id` = s.`default_address`,
            m.`updated_by` = CASE
                WHEN m.`updated_by` IS NULL OR TRIM(COALESCE(m.`updated_by`, '')) = '' THEN 'prework_location'
                ELSE CONCAT(m.`updated_by`, '; ', 'prework_location')
            END,
            m.`updated_at` = CURRENT_TIMESTAMP
        WHERE m.`cell_id` IS NULL
          AND s.`default_address` IS NOT NULL;

        -- Отдельный блок: если Address в Transactions уже есть, а Location пустой,
        -- дозаполняем Location из текущего Main.cell_id -> Warehouses.
        UPDATE `Transactions` t
        INNER JOIN `Main` m
          ON m.`ERP_ID` COLLATE utf8mb4_unicode_ci = t.`ERP_ID` COLLATE utf8mb4_unicode_ci
        INNER JOIN `Cells` c
          ON c.`id` = m.`cell_id`
        INNER JOIN `Racks` r
          ON r.`id` = c.`rack_id`
        INNER JOIN `Warehouses` w
          ON w.`id` = r.`warehouse_id`
        SET
            t.`Location` = NULLIF(
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
            ),
            t.`updated_by` = CASE
                WHEN t.`updated_by` IS NULL OR TRIM(COALESCE(t.`updated_by`, '')) = '' THEN 'prework_location'
                ELSE CONCAT(t.`updated_by`, '; ', 'prework_location')
            END,
            t.`updated_at` = CURRENT_TIMESTAMP
        WHERE t.`Address` IS NOT NULL
          AND TRIM(COALESCE(t.`Address`, '')) <> ''
          AND (t.`Location` IS NULL OR TRIM(COALESCE(t.`Location`, '')) = '')
          AND m.`cell_id` IS NOT NULL
          AND NULLIF(TRIM(COALESCE(w.`name`, '')), '') IS NOT NULL;

        DROP TEMPORARY TABLE IF EXISTS `tmp_prework_location_selected`;
        DROP TEMPORARY TABLE IF EXISTS `tmp_prework_location_candidates`;

        DO RELEASE_LOCK('lock_prework_location');
    END IF;
END$$

DELIMITER ;
