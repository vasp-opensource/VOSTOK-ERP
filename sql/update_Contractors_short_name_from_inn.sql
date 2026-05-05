-- Диагностика контрагентов, где Short_name пока равно ИНН.
-- Такие строки будут исправлены скриптом DaData после обновления tools/fill_contractors_from_dadata.*.

SELECT
    `id`,
    `INN`,
    `KPP`,
    `Short_name`,
    `Full_name`
FROM `Contractors`
WHERE `INN` IS NOT NULL
  AND TRIM(`INN`) <> ''
  AND TRIM(COALESCE(`Short_name`, '')) = TRIM(`INN`)
ORDER BY `id`;
