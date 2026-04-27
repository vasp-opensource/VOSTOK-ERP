-- Количество в переделке (доработка) на карточке Main. После Quantity_of_losses.
-- Выполнить на БД до использования NocoDB/процедур, завязанных на поле.

ALTER TABLE `Main`
    ADD COLUMN `Quantity_of_rework` bigint NOT NULL DEFAULT 0
    AFTER `Quantity_of_losses`;
