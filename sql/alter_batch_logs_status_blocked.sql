-- Добавляет статус BLOCKED в batch/performance логи.
-- Используется для блокировок: GET_LOCK busy, deadlock, lock timeout, FOR UPDATE NOWAIT.

ALTER TABLE `kernel_log`
  MODIFY COLUMN `status` ENUM('OK', 'ERROR', 'BLOCKED') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'OK';

ALTER TABLE `import_log`
  MODIFY COLUMN `status` ENUM('OK', 'ERROR', 'BLOCKED') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'OK';

ALTER TABLE `integrity_batch_log`
  MODIFY COLUMN `status` ENUM('OK', 'ERROR', 'BLOCKED') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'OK';

ALTER TABLE `import_check_log`
  MODIFY COLUMN `status` ENUM('OK', 'ERROR', 'BLOCKED') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'OK';

ALTER TABLE `recommend_log`
  MODIFY COLUMN `status` ENUM('OK', 'ERROR', 'BLOCKED') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'OK';

ALTER TABLE `supervisor_log`
  MODIFY COLUMN `status` ENUM('OK', 'ERROR', 'BLOCKED') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'OK';

ALTER TABLE `assembly_batches_log`
  MODIFY COLUMN `status` ENUM('OK', 'ERROR', 'BLOCKED') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'OK';

ALTER TABLE `bot_call_log`
  MODIFY COLUMN `status` ENUM('OK', 'ERROR', 'BLOCKED') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'OK';

ALTER TABLE `performance_log`
  MODIFY COLUMN `status` ENUM('OK', 'ERROR', 'BLOCKED') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'OK';
