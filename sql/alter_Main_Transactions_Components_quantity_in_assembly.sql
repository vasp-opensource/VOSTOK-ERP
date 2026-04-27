-- Количество компонентов в сборке для ERP_ID (снимок из Transactions при первичном создании Main; в Main не меняется).

ALTER TABLE `Main`
  ADD COLUMN `Components_quantity_in_assembly` BIGINT NOT NULL DEFAULT 0
  COMMENT 'Число компонентов, из которых состоит данный ERP_ID; переносится из Transactions при первой вставке Main'
  AFTER `Component_name`;

ALTER TABLE `Transactions`
  ADD COLUMN `Components_quantity_in_assembly` BIGINT NOT NULL DEFAULT 0
  COMMENT 'Снимок: число компонентов в сборке для ERP_ID; при копировании строк переносится с родителя'
  AFTER `Quantity_of_target_assemblies`;
