# ERP — вводные для проекта

**Путь к проекту:** `/Users/vaspy/Vostok/ERP` (этот файл: `PROJECT_CONTEXT.md` в корне проекта).

**Стек:** MySQL (phpMyAdmin), доступ пользователей через NocoDB. Бизнес-логика и пересчёты — **хранимые процедуры MySQL** по таймеру (event scheduler). В таблицу логов пишут **только процедуры**.

---

## Таблица `Main`

| Field | Type | Null | Key | Default | Extra |
|-------|------|------|-----|---------|-------|
| ERP_ID | varchar(255) | NO | UNI | NULL | |
| id | int unsigned | NO | PRI | NULL | auto_increment |
| created_at | timestamp | YES | | NULL | |
| updated_at | timestamp | YES | | NULL | |
| created_by | varchar(255) | YES | | NULL | |
| updated_by | varchar(255) | YES | | NULL | |
| Supplied_component_number | text | YES | | NULL | |
| Component_revision | text | YES | | NULL | |
| Component_name | text | YES | | NULL | |
| inProcess_purchase | bigint | NO | | 0 | |
| inProcess_manufacturing | bigint | NO | | 0 | |
| Quantity_in_warehouse | bigint | NO | | 0 | |
| Quantity_in_kitting | bigint | YES | | 0 | |
| Quantity_on_shopfloor | bigint | NO | | 0 | |
| Quantity_implemented | bigint | NO | | 0 | |
| Quantity_shipped | bigint | NO | | 0 | |
| Quantity_of_losses | bigint | NO | | 0 | |
| Quantity_of_rework | bigint | NO | | 0 | |
| Address | text | YES | | NULL | |
| cell_id | int unsigned | YES | MUL | NULL | FK на `Cells.id`; одна строка `Main` / один `ERP_ID` хранится в одной ячейке |
| Component_type | text | YES | | NULL | |
| Components_quantity_in_assembly | bigint | NO | | 0 | Число компонентов в сборке для данного ERP_ID; при первичном создании строки переносится из Transactions, далее не меняется |
| Part_material | text | YES | | NULL | |
| Producer | text | YES | | NULL | |
| Catalogue_number | text | YES | | NULL | |
| Producer_article | text | YES | | NULL | |
| Distributer | text | YES | | NULL | |
| Distributer_article | text | YES | | NULL | |
| MBOM_type | text | YES | | NULL | |
| Mass_kg | double(14,6) | YES | | NULL | |
| Unit_of_measure | text | YES | | NULL | |
| Height | double | YES | | NULL | |
| Width | double | YES | | NULL | |
| Length | double | YES | | NULL | |
| Price_min | decimal(15,4) | YES | | NULL | |
| Price_max | decimal(15,4) | YES | | NULL | |
| Source | enum('Покупное','Собственное производство') | YES | | NULL | |

**Смысл:** одна строка — один компонент; `ERP_ID` уникален; `Components_quantity_in_assembly` задаётся при первой вставке строки из данных `Transactions` и дальше не пересчитывается процедурами; агрегированные количества по этапам (закупка, производство, склад, комплектация, цех, внедрение, отгрузка, потери); `cell_id` задаёт ячейку хранения через справочник `Cells`; `Address` остаётся текстовым снимком адреса ячейки для совместимости с текущими процедурами; при заполнении/уточнении `Main.cell_id` все `Transactions.Address` с тем же `ERP_ID` обновляются текущим `Main.Address`; `Price_min` / `Price_max` — диапазон цены за единицу (руб.), если используется.

**Сортировка в списках (NocoDB / отчёты):** по полю `ERP_ID` по возрастанию.

---

## Адресное хранение

Миграция: `sql/create_storage_locations.sql`.

Обработчик `sql/prework_address.sql` заполняет пустой `Transactions.Address` из назначенной ячейки `Main.cell_id -> Cells.address_code` для строк с тем же `ERP_ID`; `Main.Address` используется как текстовый fallback. Обёртка `sql/schedule_batch_prework.sql` запускается в основном цикле оркестратора после `batch_import` и до `batch_recommend`; в ней также вызывается `ch_unite_same_advGroup`, чтобы объединять новые change-заявки только внутри связки `ERP_ID + Project + Advanced_group`.

### Таблица `Warehouses`

| Field | Type | Null | Key | Default | Extra |
|-------|------|------|-----|---------|-------|
| id | int unsigned | NO | PRI | NULL | auto_increment |
| created_at | timestamp | YES | | CURRENT_TIMESTAMP | |
| updated_at | timestamp | YES | | CURRENT_TIMESTAMP | ON UPDATE CURRENT_TIMESTAMP |
| warehouse_no | int unsigned | NO | UNI | NULL | Номер склада для кода `W{warehouse_no}` |
| name | varchar(255) | YES | | NULL | |
| comment | text | YES | | NULL | Техническая информация: почтовый адрес, описание зоны и т.п. |

### Таблица `Racks`

| Field | Type | Null | Key | Default | Extra |
|-------|------|------|-----|---------|-------|
| id | int unsigned | NO | PRI | NULL | auto_increment |
| created_at | timestamp | YES | | CURRENT_TIMESTAMP | |
| updated_at | timestamp | YES | | CURRENT_TIMESTAMP | ON UPDATE CURRENT_TIMESTAMP |
| warehouse_id | int unsigned | NO | MUL | NULL | FK на `Warehouses.id` |
| rack_no | int unsigned | NO | | NULL | Номер стеллажа для кода `R{rack_no}` |
| name | varchar(255) | YES | | NULL | |
| comment | text | YES | | NULL | Техническая информация по стеллажу |

Уникальность: `warehouse_id + rack_no`.

### Таблица `Cells`

| Field | Type | Null | Key | Default | Extra |
|-------|------|------|-----|---------|-------|
| id | int unsigned | NO | PRI | NULL | auto_increment |
| created_at | timestamp | YES | | CURRENT_TIMESTAMP | |
| updated_at | timestamp | YES | | CURRENT_TIMESTAMP | ON UPDATE CURRENT_TIMESTAMP |
| rack_id | int unsigned | NO | MUL | NULL | FK на `Racks.id` |
| cell_no | int unsigned | NO | | NULL | Номер ячейки для кода `C{cell_no}` |
| address_code | varchar(64) | YES | UNI | NULL | Автоматически собирается триггером как `W2R3C25`; NULL разрешён, чтобы NocoDB не требовал ручной ввод |
| comment | text | YES | | NULL | Техническая информация: особые приметы, ограничения, пометки |

Уникальность: `rack_id + cell_no` и `address_code`.

---

## Таблица `Transactions`

| Field | Type | Null | Key | Default | Extra |
|-------|------|------|-----|---------|-------|
| ERP_ID | varchar(255) | NO | | NULL | |
| id | int unsigned | NO | PRI | NULL | auto_increment |
| created_at | timestamp | YES | | CURRENT_TIMESTAMP | DEFAULT_GENERATED |
| updated_at | timestamp | YES | | CURRENT_TIMESTAMP | DEFAULT_GENERATED |
| created_by | varchar(255) | YES | | Export user | |
| updated_by | text | YES | | NULL | |
| linked_transaction | text | YES | | NULL | Цепочка id через «; » (не перезаписывать — дописывать) |
| type | enum('change','move') | YES | | change | |
| where_from | enum('внешний','закупка','склад','цех','собственное производство') | NO | | внешний | |
| where_to | enum('закупка','склад','цех','собственное производство','отгрузка','брак','изделие','доработка') | NO | | закупка | |
| Quantity_of_parts_total | bigint | NO | | 0 | |
| Quantity_change | bigint | NO | | 0 | |
| Status_transaction | enum('В ожидании','Исполнено','Отменено','Заменено','Заменен ID') | YES | | В ожидании | |
| Status_warehouse | enum('Норма','Дефицит склада','Ожидание закупки','Ожидание изготовления','Дефицит поставки','Комплектация','В закупке','В изготовлении','Новая','Утилизация','Сборка','Упаковка','Ожидание поставки','Ожидает решения','Доработка') | YES | | NULL | |
| Project | text | YES | | NULL | |
| Target_assembly | text | YES | | NULL | |
| Supplied_component_number | text | YES | | NULL | |
| Component_revision | text | YES | | NULL | |
| Component_name | text | YES | | NULL | |
| Quantity_in_target_assembly | bigint | NO | | 0 | |
| Quantity_of_target_assemblies | bigint | NO | | 0 | |
| Component_type | text | YES | | NULL | |
| For_supplied_as_assembly_components_provided_by_supplier | text | YES | | NULL | |
| Components_quantity_in_assembly | int | NO | | 0 | Снимок: сколько компонентов в сборке для данного ERP_ID; при дочерних move/change копируется с исходной строки |
| Assembly_batch_id | varchar(255) | YES | | NULL | |
| Assembly_batch_name | text | YES | | NULL | |
| Assembly_batch_status | enum('Нет спецификации','Ожидает определения','В закупке/изготовлении','В комплектации','В сборке','Готов','Завершен') | YES | | NULL | |
| Assembly_batch_priority | int | YES | | NULL | |
| Part_material | text | YES | | NULL | |
| Producer | text | YES | | NULL | |
| Catalogue_number | text | YES | | NULL | |
| Producer_article | text | YES | | NULL | |
| Distributer | text | YES | | NULL | |
| Distributer_article | text | YES | | NULL | |
| MBOM_type | text | YES | | NULL | |
| Mass_kg | double | YES | | NULL | |
| Unit_of_measure | text | YES | | NULL | |
| Height | double | YES | | NULL | |
| Width | double | YES | | NULL | |
| Length | double | YES | | NULL | |
| Advanced_group | text | YES | | NULL | |
| Address | text | YES | | NULL | |
| Recommend_purchprod | enum('В закупку','В собственное производство','Уточнить кол-во в изготовлении','Уточнить кол-во в закупке','Уточнить ревизию','Уточнить ревизию в изготовлении','Уточнить ревизию в закупке') | YES | | NULL | |
| Order_purch | enum('Ожидание закупки','В закупке','Оплачено','Собственное производство','Проблема') | YES | | Ожидание закупки | |
| Order_wh | enum('Принято на склад','В комплектации','Списано со склада','Проблема') | YES | | NULL | |
| Order_prod | enum('В закупку','Принято со склада','Проблема','Принято в изготовление','Изготовлено','Вернуть на склад','Отгружено','Забраковать') | YES | | NULL | |
| Order_OTK | enum('Принято','Забраковано','В доработку') | YES | | NULL | |
| Order_sv | enum('разбить','забраковать','отменить','доработать запас','заменить со склада','заменить и восполнить','вернуть в закупку/изготовление') | YES | | NULL | |
| Recommend_wh | text | YES | | NULL | |
| Quantity_ordered | bigint | NO | | 0 | |
| Replace_to | text | YES | | NULL | |
| Rework_to | text | YES | | NULL | |
| Rework_from | text | YES | | NULL | |
| Document_no | text | YES | | NULL | |
| Document_date | date | YES | | NULL | Дата закрывающего документа |
| Document_id | int unsigned | YES | MUL | NULL | FK на `Documents.id` |
| Zakaz_no | text | YES | | NULL | |
| Date_needed | date | YES | | NULL | |
| Date_expected | date | YES | | NULL | |
| Cost_total_rub | float | YES | | NULL | |
| Supplier | enum('ИТЦ','ОДИН КИТАЕЦ') | YES | | NULL | |
| Contractor_id | int unsigned | YES | MUL | NULL | FK на `Contractors.id` |
| Price_of_single_unit | double | YES | | NULL | VIRTUAL: `Cost_total_rub / Quantity_change`, если `Quantity_change` ≠ 0 и не NULL, иначе NULL |
| Location | text | YES | | NULL | |
| Source | enum('Покупное','Собственное производство') | YES | | NULL | |
| Initial_doc_no | text | YES | | NULL | |

**Смысл:** журнал движений/изменений; связь с номенклатурой по `ERP_ID`; `linked_transaction` — цепочка id связанных строк (через `; `, не перезаписывать); `Components_quantity_in_assembly` — снимок для данного ERP_ID (число компонентов в сборке), при порождении дочерних строк копируется с родителя; реквизиты компонента дублируются как снимок на момент операции.

**Сортировка в списках (NocoDB / отчёты):** по полю `ERP_ID` по возрастанию, при необходимости вторично по `id`. Для ускорения сортировки и фильтра выполните миграцию `sql/alter_transactions_index_erp_id.sql` (индекс `idx_erp_id`), если его ещё нет в БД.

---

## Таблица логов (имя БД — уточнить при необходимости)

| Field | Type | Null | Key | Default | Extra |
|-------|------|------|-----|---------|-------|
| id | bigint unsigned | NO | PRI | NULL | auto_increment |
| created_at | timestamp | NO | MUL | CURRENT_TIMESTAMP | DEFAULT_GENERATED |
| level | enum('INFO','WARN','ERROR') | NO | | ERROR | |
| message | text | NO | | NULL | |
| tx_id | int | YES | MUL | NULL | |
| erp_id | varchar(255) | YES | MUL | NULL | |

**Смысл:** логи процедур; `tx_id` — ссылка на `Transactions.id`; в процедурах явно задавать `level`, иначе попадёт DEFAULT `ERROR`.

---

## Актуальные формулы дефицита (`deficit_wh`, `deficit_supply`)

Переменные расчёта по `ERP_ID`:

- Доступное количество = `Main.Quantity_in_warehouse`
- Ожидание поставок = `SUM(Transactions.Quantity_change)` для `type='change'`, `where_from='внешний'`, `where_to='склад'`, `Status_transaction='В ожидании'`, `Status_warehouse='Новая'`
- Потребность поставок = `SUM(Transactions.Quantity_of_parts_total)` для `type='move'`, `where_from='склад'`, `where_to in ('брак','отгрузка','изделие')`, `Status_transaction='В ожидании'`, `Status_warehouse in ('Новая','Ожидание поставки')`
- Ожидание закупок = `SUM(Transactions.Quantity_change)` для `type='change'`, `where_from='внешний'`, `where_to='склад'`, `Status_transaction='В ожидании'`, `Status_warehouse='В закупке'`
- Ожидание изготовления = `SUM(Transactions.Quantity_change)` для `type='change'`, `where_from='внешний'`, `where_to='склад'`, `Status_transaction='В ожидании'`, `Status_warehouse='В изготовлении'`
- Потребность закупок = `SUM(Transactions.Quantity_of_parts_total)` для `type='move'`, `Status_transaction='В ожидании'`, `Status_warehouse='Ожидание закупки'`
- Потребность изготовления = `SUM(Transactions.Quantity_of_parts_total)` для `type='move'`, `Status_transaction='В ожидании'`, `Status_warehouse='Ожидание изготовления'`

Итоги:

- Доступное ожидаемое поступление = `(Ожидание закупок - Потребность закупок) + (Ожидание изготовления - Потребность изготовления) + (Ожидание поставок - Потребность поставок)`
- Общее количество = `Доступное количество + Доступное ожидаемое поступление`

Порядок обработки строк:

- Построчно (без объединения по `Target_assembly`)
- Приоритет `where_to`: `брак` -> `отгрузка` -> `изделие`

---

## Как пользоваться в Cursor в следующий раз

1. Открыть этот файл или в чате указать **`@PROJECT_CONTEXT.md`** — контекст подтянется в разговор.
2. При желании добавить правило в **Cursor Rules** (`.cursor/rules/`) со ссылкой «схема в `PROJECT_CONTEXT.md`» — тогда модель будет ориентироваться на проект чаще автоматически.

*Файл можно дополнять: имя БД, имена процедур и событий scheduler, договорённости по пересчёту `Main` из `Transactions`.*
