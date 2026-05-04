-- bot_parameters: настраиваемые диапазоны случайных параметров и текстовые параметры ботов.
-- Для числовых параметров bot_call генерирует целое значение в диапазоне [value_min..value_max].
-- Для Projects используется text_parameter: CSV-список проектов, видимых ботам, например 0011, 0012, 0014.

CREATE TABLE IF NOT EXISTS `bot_parameters` (
    `variable_name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
    `value_min` bigint NULL,
    `value_max` bigint NULL,
    `text_parameter` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
    `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`variable_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT IGNORE INTO `bot_parameters` (`variable_name`, `value_min`, `value_max`, `text_parameter`)
VALUES
    ('Projects', NULL, NULL, '0011, 0012, 0014'),
    ('exp_row_count', 5, 15, NULL),
    ('exp_approve', 5, 15, NULL),
    ('purch_purch', 5, 15, NULL),
    ('purch_byed', 5, 15, NULL),
    ('purch_manuf', 0, 1, NULL),
    ('prod_rework', 0, 1, NULL),
    ('purch_return', 0, 1, NULL),
    ('purch_cost', 5000, 150000, NULL),
    ('prod_kit', 5, 15, NULL),
    ('prod_assembled', 3, 14, NULL),
    ('prod_prod', 1, 4, NULL),
    ('prod_manuf', 1, 4, NULL),
    ('prod_purch', 0, 1, NULL),
    ('prod_shipped', 0, 1, NULL),
    ('prod_loss', 0, 1, NULL),
    ('prod_return', 0, 1, NULL),
    ('wh_purch', 5, 15, NULL),
    ('wh_manuf', 5, 15, NULL),
    ('wh_return', 5, 15, NULL),
    ('wh_kit', 5, 15, NULL),
    ('OTK_manuf', 5, 15, NULL),
    ('OTK_assembly', 5, 15, NULL),
    ('OTK_shipped', 5, 15, NULL),
    ('OTK_loss', 5, 15, NULL),
    ('sv_choice', 0, 3, NULL),
    ('sv_replace', 0, 5, NULL);

GRANT SELECT ON `VOSTOK_ERP`.`bot_parameters` TO 'export'@'%';
GRANT SELECT ON `VOSTOK_ERP`.`bot_parameters` TO 'bot_ERP'@'%';
