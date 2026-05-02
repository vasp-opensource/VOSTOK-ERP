-- Диагностика для recommend_change_new: показывает остаток строк и прямые совпадения с правилами.
-- Запускать после create_table_recommend_rules.sql и перед/после CALL recommend_call().

SELECT
    COUNT(*) AS empty_recommend_candidates
FROM `Transactions` t
WHERE t.`type` = 'change'
  AND t.`Status_transaction` = 'В ожидании'
  AND t.`Status_warehouse` = 'Новая'
  AND (t.`Recommend_purchprod` IS NULL OR t.`Recommend_purchprod` = '');

SELECT
    t.`id`,
    t.`ERP_ID`,
    t.`Project`,
    t.`Component_type`,
    t.`MBOM_type`,
    r.`rule_id`,
    r.`recommend_purchprod`,
    r.`priority`,
    r.`field_name`,
    r.`compare_operator`,
    r.`condition_value`
FROM `Transactions` t
INNER JOIN `recommend_rules` r
    ON (r.`project` COLLATE utf8mb4_unicode_ci = 'ANY' COLLATE utf8mb4_unicode_ci
        OR FIND_IN_SET(
            TRIM(COALESCE(CAST(t.`Project` AS CHAR CHARACTER SET utf8mb4), '')) COLLATE utf8mb4_unicode_ci,
            REPLACE(CAST(r.`project` AS CHAR CHARACTER SET utf8mb4), ', ', ',') COLLATE utf8mb4_unicode_ci
        ) > 0)
   AND (
        r.`field_name` COLLATE utf8mb4_unicode_ci = 'ANY' COLLATE utf8mb4_unicode_ci
        OR (r.`field_name` COLLATE utf8mb4_unicode_ci = 'Component_type' COLLATE utf8mb4_unicode_ci
            AND r.`compare_operator` COLLATE utf8mb4_unicode_ci = '=' COLLATE utf8mb4_unicode_ci
            AND TRIM(COALESCE(CAST(t.`Component_type` AS CHAR CHARACTER SET utf8mb4), '')) COLLATE utf8mb4_unicode_ci
                = TRIM(CAST(r.`condition_value` AS CHAR CHARACTER SET utf8mb4)) COLLATE utf8mb4_unicode_ci)
        OR (r.`field_name` COLLATE utf8mb4_unicode_ci = 'Component_type' COLLATE utf8mb4_unicode_ci
            AND r.`compare_operator` COLLATE utf8mb4_unicode_ci = 'like' COLLATE utf8mb4_unicode_ci
            AND TRIM(COALESCE(CAST(t.`Component_type` AS CHAR CHARACTER SET utf8mb4), '')) COLLATE utf8mb4_unicode_ci
                LIKE CONCAT('%', TRIM(CAST(r.`condition_value` AS CHAR CHARACTER SET utf8mb4)), '%') COLLATE utf8mb4_unicode_ci)
        OR (r.`field_name` COLLATE utf8mb4_unicode_ci = 'MBOM_type' COLLATE utf8mb4_unicode_ci
            AND r.`compare_operator` COLLATE utf8mb4_unicode_ci = '=' COLLATE utf8mb4_unicode_ci
            AND TRIM(COALESCE(CAST(t.`MBOM_type` AS CHAR CHARACTER SET utf8mb4), '')) COLLATE utf8mb4_unicode_ci
                = TRIM(CAST(r.`condition_value` AS CHAR CHARACTER SET utf8mb4)) COLLATE utf8mb4_unicode_ci)
        OR (r.`field_name` COLLATE utf8mb4_unicode_ci = 'MBOM_type' COLLATE utf8mb4_unicode_ci
            AND r.`compare_operator` COLLATE utf8mb4_unicode_ci = 'like' COLLATE utf8mb4_unicode_ci
            AND TRIM(COALESCE(CAST(t.`MBOM_type` AS CHAR CHARACTER SET utf8mb4), '')) COLLATE utf8mb4_unicode_ci
                LIKE CONCAT('%', TRIM(CAST(r.`condition_value` AS CHAR CHARACTER SET utf8mb4)), '%') COLLATE utf8mb4_unicode_ci)
   )
WHERE t.`type` = 'change'
  AND t.`Status_transaction` = 'В ожидании'
  AND t.`Status_warehouse` = 'Новая'
  AND (t.`Recommend_purchprod` IS NULL OR t.`Recommend_purchprod` = '')
ORDER BY t.`id`, r.`priority`
LIMIT 100;
