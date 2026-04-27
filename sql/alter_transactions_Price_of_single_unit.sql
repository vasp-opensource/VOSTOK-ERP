-- Расчётная колонка: цена за единицу = Cost_total_rub / Quantity_change при Quantity_change <> 0, иначе NULL.

-- Если раньше уже добавили столбец с опечаткой Price_of_singe_unit — сначала удалите его:
-- ALTER TABLE `Transactions` DROP COLUMN `Price_of_singe_unit`;

ALTER TABLE `Transactions`
ADD COLUMN `Price_of_single_unit` DOUBLE GENERATED ALWAYS AS (
  CASE
    WHEN `Quantity_change` IS NOT NULL AND `Quantity_change` <> 0
    THEN `Cost_total_rub` / CAST(`Quantity_change` AS DOUBLE)
    ELSE NULL
  END
) VIRTUAL;
