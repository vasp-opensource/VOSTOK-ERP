-- recommend_call: единая точка запуска рекомендаций; сейчас вызывает только recommend_change_purchprod.
-- Требуется на БД: recommend_change_new.sql и recommend_change_purchprod.sql.
DELIMITER $$

DROP PROCEDURE IF EXISTS `recommend_call`$$

CREATE PROCEDURE `recommend_call`()
BEGIN
  CALL `recommend_change_purchprod`();
END$$

DELIMITER ;
