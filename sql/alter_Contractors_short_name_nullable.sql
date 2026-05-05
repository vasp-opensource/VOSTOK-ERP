-- Contractors.Short_name: разрешить пустое имя при создании карточки только по ИНН.
-- Название затем заполняется внешним скриптом DaData.

ALTER TABLE `Contractors`
    MODIFY COLUMN `Short_name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL;
