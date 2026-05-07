-- Приводит Transactions.Location к TEXT (вместо ENUM), чтобы разрешить произвольные значения локации.

ALTER TABLE `Transactions`
    MODIFY COLUMN `Location` TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL;
