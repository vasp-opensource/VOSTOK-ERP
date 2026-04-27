DROP PROCEDURE IF EXISTS move_waite_for_supply;

DELIMITER $$

CREATE PROCEDURE move_waite_for_supply()
BEGIN
    UPDATE `Transactions`
       SET Status_warehouse = 'Новая'
     WHERE type = 'move'
       AND where_from = 'склад'
       AND where_to IN ('брак', 'отгрузка', 'изделие')
       AND Status_warehouse = 'Ожидание поставки';
END$$

DELIMITER ;
