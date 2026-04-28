-- recommend_call: единая точка запуска рекомендаций.
-- Требуется на БД: supervisor_order.sql, recommend_change_new.sql,
-- recommend_change_purchprod.sql, recommend_rework.sql и recommend_change_wh.sql.
DELIMITER $$

DROP PROCEDURE IF EXISTS `recommend_call`$$

CREATE PROCEDURE `recommend_call`()
BEGIN
  CALL `supervisor_order`();
  CALL `recommend_change_purchprod`();
  CALL `recommend_change_wh`();
END$$

DELIMITER ;
