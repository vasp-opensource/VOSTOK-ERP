-- Main: минимальная и максимальная цена за единицу (руб.), заполняются по бизнес-логике / процедурам.

ALTER TABLE `Main`
  ADD COLUMN `Price_min` DECIMAL(15, 4) NULL DEFAULT NULL AFTER `Length`,
  ADD COLUMN `Price_max` DECIMAL(15, 4) NULL DEFAULT NULL AFTER `Price_min`;
