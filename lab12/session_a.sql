-- Практическая работа № 12. Сеанс A (PID при эксперименте: 163).


-- 1. Проверка независимого подключения (в опыте получено PID 163).
SELECT pg_backend_pid();

-- 2. Потерянное обновление (READ COMMITTED).
-- A2.1. Восстановить qty и прочитать его до изменения в B.
UPDATE lab.inventory SET qty = 10, version = 0
WHERE product_id = (SELECT product_id FROM lab.lab12_targets WHERE target_code = 'P1');
BEGIN ISOLATION LEVEL READ COMMITTED;
SELECT qty FROM lab.inventory
WHERE product_id = (SELECT product_id FROM lab.lab12_targets WHERE target_code = 'P1');
-- ПАУЗА: в B выполнить B2.1 (прочитать 10, оставить транзакцию открытой).
-- A2.2. Записать вычисленную по старому значению константу 9.
UPDATE lab.inventory SET qty = 9
WHERE product_id = (SELECT product_id FROM lab.lab12_targets WHERE target_code = 'P1');
COMMIT;
-- ПАУЗА: в B выполнить B2.2 (тоже записать 9) и COMMIT.
-- A2.3. Итог 9 вместо 8.
SELECT qty AS lost_update_qty FROM lab.inventory
WHERE product_id = (SELECT product_id FROM lab.lab12_targets WHERE target_code = 'P1');

-- 3. SELECT FOR UPDATE (READ COMMITTED).
-- A3.1. После завершения опыта № 2 восстановить qty=10.
UPDATE lab.inventory SET qty = 10, version = 0
WHERE product_id = (SELECT product_id FROM lab.lab12_targets WHERE target_code = 'P1');
BEGIN;
SELECT qty FROM lab.inventory
WHERE product_id = (SELECT product_id FROM lab.lab12_targets WHERE target_code = 'P1')
FOR UPDATE;
-- ПАУЗА: в B выполнить B3.1; SELECT ... FOR UPDATE будет ждать.
-- A3.2. Списать одну единицу и освободить блокировку.
UPDATE lab.inventory SET qty = qty - 1, version = version + 1
WHERE product_id = (SELECT product_id FROM lab.lab12_targets WHERE target_code = 'P1');
COMMIT;
-- ПАУЗА: в B SELECT покажет 9; затем B3.2 спишет ещё единицу и COMMIT.
SELECT qty AS locked_updates_qty FROM lab.inventory
WHERE product_id = (SELECT product_id FROM lab.lab12_targets WHERE target_code = 'P1');
-- Ожидается 8.

-- 4. Атомарное резервирование без предварительного FOR UPDATE.
-- A4.1. Восстановить qty=10 и выполнить UPDATE без COMMIT.
UPDATE lab.inventory SET qty = 10, version = 0
WHERE product_id = (SELECT product_id FROM lab.lab12_targets WHERE target_code = 'P1');
BEGIN;
UPDATE lab.inventory
SET qty = qty - 1, version = version + 1
WHERE product_id = (SELECT product_id FROM lab.lab12_targets WHERE target_code = 'P1')
  AND qty > 0
RETURNING qty;
-- ПАУЗА: B4.1 делает такой же UPDATE и ожидает.
-- A4.2. Освободить строку.
COMMIT;
-- ПАУЗА: B4.2 получает 8 и выполняет COMMIT.
SELECT qty, version FROM lab.inventory
WHERE product_id = (SELECT product_id FROM lab.lab12_targets WHERE target_code = 'P1');
-- Ожидается qty=8, version=2.

-- 5. Неповторяемое чтение при READ COMMITTED.
-- A5.1. Восстановить остаток; прочитать 10.
UPDATE lab.inventory SET qty = 10, version = 0
WHERE product_id = (SELECT product_id FROM lab.lab12_targets WHERE target_code = 'P1');
BEGIN ISOLATION LEVEL READ COMMITTED;
SELECT qty AS first_read_rc FROM lab.inventory
WHERE product_id = (SELECT product_id FROM lab.lab12_targets WHERE target_code = 'P1');
-- ПАУЗА: B5.1 устанавливает 7 и фиксирует транзакцию.
-- A5.2. При втором SELECT видно уже 7.
SELECT qty AS second_read_rc FROM lab.inventory
WHERE product_id = (SELECT product_id FROM lab.lab12_targets WHERE target_code = 'P1');
COMMIT;

-- 6. Повторяемое чтение при REPEATABLE READ.
-- A6.1. Восстановить 10, открыть транзакцию, прочитать 10.
UPDATE lab.inventory SET qty = 10, version = 0
WHERE product_id = (SELECT product_id FROM lab.lab12_targets WHERE target_code = 'P1');
BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT qty AS first_read_rr FROM lab.inventory
WHERE product_id = (SELECT product_id FROM lab.lab12_targets WHERE target_code = 'P1');
-- ПАУЗА: B6.1 устанавливает 7 и выполняет COMMIT.
-- A6.2. Повторное чтение в этой транзакции всё ещё показывает 10.
SELECT qty AS second_read_rr FROM lab.inventory
WHERE product_id = (SELECT product_id FROM lab.lab12_targets WHERE target_code = 'P1');
COMMIT;
SELECT qty AS after_rr_commit FROM lab.inventory
WHERE product_id = (SELECT product_id FROM lab.lab12_targets WHERE target_code = 'P1');
-- После завершения транзакции отображается 7.

-- 7. Фантомное чтение при READ COMMITTED.
-- В реальной таблице lab.inventory_movements есть qty_delta, но НЕТ movement_type.
-- A7.1. Прочитать количество отрицательных движений (в опыте 0).
BEGIN ISOLATION LEVEL READ COMMITTED;
SELECT COUNT(*) AS movement_count
FROM lab.inventory_movements
WHERE qty_delta < 0;
-- ПАУЗА: B7.1 INSERT одной строки qty_delta=-1 и COMMIT.
-- A7.2. Повторный COUNT (в опыте 1).
SELECT COUNT(*) AS movement_count
FROM lab.inventory_movements
WHERE qty_delta < 0;
COMMIT;

-- 8. Взаимная блокировка (deadlock).
-- Обе транзакции до начала должны быть завершены.
-- A8.1. Заблокировать товар P1.
BEGIN;
SELECT i.qty
FROM lab.inventory AS i
JOIN lab.lab12_targets AS t ON t.product_id = i.product_id
WHERE t.target_code = 'P1'
FOR UPDATE OF i;
-- ПАУЗА: B8.1 блокирует P2.
-- A8.2. Попытаться блокировать P2: этот SELECT будет ждать.
SELECT i.qty
FROM lab.inventory AS i
JOIN lab.lab12_targets AS t ON t.product_id = i.product_id
WHERE t.target_code = 'P2'
FOR UPDATE OF i;
-- ПОКА A ждёт: B8.2 пытается блокировать P1 и получает deadlock detected.
-- В проведённом опыте B получил ошибку, затем B сделал ROLLBACK.
-- После этого запрос A завершился: qty P2=10. В A выполнить:
COMMIT;

-- 9*. SERIALIZABLE; ошибка обновления строки, прочитанной двумя транзакциями.
-- A9.1. После обоих завершённых сеансов установить P1 и P2 по 10.
UPDATE lab.inventory SET qty = 10, version = 0
WHERE product_id IN (
    SELECT product_id FROM lab.lab12_targets WHERE target_code IN ('P1','P2')
);
BEGIN ISOLATION LEVEL SERIALIZABLE;
SELECT t.target_code, i.qty
FROM lab.inventory AS i JOIN lab.lab12_targets AS t USING (product_id)
WHERE t.target_code IN ('P1','P2') ORDER BY t.target_code;
-- ПАУЗА: B9.1 начинает SERIALIZABLE и читает те же 10, 10.
-- A9.2. Изменить P1 и зафиксировать транзакцию.
UPDATE lab.inventory SET qty = qty - 1, version = version + 1
WHERE product_id = (SELECT product_id FROM lab.lab12_targets WHERE target_code = 'P1')
RETURNING qty;
COMMIT;
-- ПАУЗА: B9.2 пытается изменить P1 по старому снимку -> serialization_failure.
-- B9.3 ROLLBACK, новая транзакция SERIALIZABLE, повтор UPDATE, COMMIT -> P1=8.
SELECT t.target_code, i.qty, i.version
FROM lab.inventory AS i JOIN lab.lab12_targets AS t USING (product_id)
WHERE t.target_code IN ('P1','P2') ORDER BY t.target_code;

-- 10. Очистка после завершения всех опытов.
-- Выполнять ТОЛЬКО после окончания экспериментов и завершения всех транзакций.
UPDATE lab.inventory SET qty = 10, version = 0
WHERE product_id IN (
    SELECT product_id FROM lab.lab12_targets WHERE target_code IN ('P1','P2')
);
-- В проведённом опыте был ровно один тестовый отрицательный movement P1.
DELETE FROM lab.inventory_movements
WHERE product_id = (SELECT product_id FROM lab.lab12_targets WHERE target_code = 'P1')
  AND qty_delta = -1;
SELECT t.target_code, i.qty, i.version
FROM lab.inventory AS i JOIN lab.lab12_targets AS t USING (product_id)
WHERE t.target_code IN ('P1','P2') ORDER BY t.target_code;
SELECT COUNT(*) AS negative_qty_count FROM lab.inventory WHERE qty < 0;
-- В проведённом опыте: DELETE 1, P1/P2 = 10/0, negative_qty_count = 0.
