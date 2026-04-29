-- assembly_batch_call: единая точка запуска процедур сборочных партий.

DELIMITER $$

DROP PROCEDURE IF EXISTS `assembly_batch_call`$$

CREATE PROCEDURE `assembly_batch_call`()
BEGIN
  CALL `assembly_batch_set`();
  CALL `Assembly_batch_collect`();
END$$

DELIMITER ;
