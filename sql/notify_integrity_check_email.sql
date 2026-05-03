-- Уведомления по e-mail о новых записях в integrity_check_log.
-- Реализация через outbox-таблицу (email_outbox), чтобы отправку выполнял внешний сервис/скрипт.

CREATE TABLE IF NOT EXISTS `email_outbox` (
    `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `recipient` VARCHAR(255) NOT NULL,
    `subject` VARCHAR(255) NOT NULL,
    `body` LONGTEXT NOT NULL,
    `status` ENUM('NEW','SENT','ERROR') NOT NULL DEFAULT 'NEW',
    `source` VARCHAR(64) NOT NULL DEFAULT 'integrity_check_log',
    `related_from_id` BIGINT UNSIGNED NULL,
    `related_to_id` BIGINT UNSIGNED NULL,
    PRIMARY KEY (`id`),
    KEY `idx_email_outbox_status_created_at` (`status`, `created_at`),
    KEY `idx_email_outbox_source` (`source`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `integrity_email_state` (
    `singleton_id` TINYINT UNSIGNED NOT NULL,
    `last_sent_id` BIGINT UNSIGNED NOT NULL DEFAULT 0,
    `last_sent_at` DATETIME NULL,
    PRIMARY KEY (`singleton_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT IGNORE INTO `integrity_email_state` (`singleton_id`, `last_sent_id`, `last_sent_at`)
VALUES (1, 0, NULL);

DELIMITER $$

DROP PROCEDURE IF EXISTS notify_integrity_check_email$$

CREATE PROCEDURE notify_integrity_check_email(
    IN p_recipient VARCHAR(255)
)
BEGIN
    DECLARE v_last_sent_id BIGINT UNSIGNED DEFAULT 0;
    DECLARE v_max_id BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_cnt BIGINT UNSIGNED DEFAULT 0;
    DECLARE v_subject VARCHAR(255);
    DECLARE v_body LONGTEXT;
    DECLARE v_old_gc BIGINT UNSIGNED DEFAULT 1024;

    START TRANSACTION;

    SELECT `last_sent_id`
      INTO v_last_sent_id
    FROM `integrity_email_state`
    WHERE `singleton_id` = 1
    FOR UPDATE;

    SELECT
        MAX(l.`id`) AS max_id,
        COUNT(*)    AS cnt_new
      INTO v_max_id, v_cnt
    FROM `integrity_check_log` l
    WHERE l.`id` > v_last_sent_id;

    IF v_cnt > 0 THEN
        SET v_old_gc = @@SESSION.group_concat_max_len;
        SET SESSION group_concat_max_len = 200000;

        SET v_subject = CONCAT('[ERP] Integrity alerts: ', v_cnt, ' new');

        SELECT
            GROUP_CONCAT(
                CONCAT(
                    '#', q.`id`,
                    ' | ', DATE_FORMAT(q.`created_at`, '%Y-%m-%d %H:%i:%s'),
                    ' | ERP_ID=', COALESCE(q.`ERP_ID`, '-'),
                    ' | ', q.`error_message`
                )
                ORDER BY q.`id`
                SEPARATOR '\n'
            )
          INTO v_body
        FROM (
            SELECT l.`id`, l.`created_at`, l.`ERP_ID`, l.`error_message`
            FROM `integrity_check_log` l
            WHERE l.`id` > v_last_sent_id
            ORDER BY l.`id`
            LIMIT 200
        ) q;

        IF v_cnt > 200 THEN
            SET v_body = CONCAT(
                COALESCE(v_body, ''),
                '\n... and ', (v_cnt - 200), ' more rows not shown.'
            );
        END IF;

        INSERT INTO `email_outbox` (
            `recipient`, `subject`, `body`, `status`, `source`, `related_from_id`, `related_to_id`
        )
        VALUES (
            p_recipient,
            v_subject,
            COALESCE(v_body, '[No details generated]'),
            'NEW',
            'integrity_check_log',
            v_last_sent_id + 1,
            v_max_id
        );

        UPDATE `integrity_email_state`
           SET `last_sent_id` = v_max_id,
               `last_sent_at` = NOW()
         WHERE `singleton_id` = 1;

        SET SESSION group_concat_max_len = v_old_gc;
    END IF;

    COMMIT;
END$$

DELIMITER ;
