-- Связь Documents с Contractors.
-- Один документ относится к одному контрагенту; один контрагент может иметь много документов.
--
-- Для существующей БД колонка добавляется NULL, чтобы миграция не падала на уже заведённых документах.
-- После заполнения Contractor_id во всех строках можно выполнить:
-- ALTER TABLE `Documents` MODIFY COLUMN `Contractor_id` int unsigned NOT NULL COMMENT 'Контрагент документа';

ALTER TABLE `Documents`
    ADD COLUMN `Contractor_id` int unsigned NULL
        COMMENT 'Контрагент документа'
        AFTER `Document_type`;

ALTER TABLE `Documents`
    ADD KEY `idx_documents_contractor_id` (`Contractor_id`);

ALTER TABLE `Documents`
    ADD CONSTRAINT `fk_documents_contractor`
        FOREIGN KEY (`Contractor_id`) REFERENCES `Contractors` (`id`)
        ON UPDATE CASCADE
        ON DELETE RESTRICT;
