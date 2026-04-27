-- Удаление столбцов Transactions: Imported, nc_order, Order_shipment (см. PROJECT_CONTEXT.md).

ALTER TABLE `Transactions`
  DROP COLUMN `Imported`,
  DROP COLUMN `nc_order`,
  DROP COLUMN `Order_shipment`;
