-- Практическая работа № 12. Сеанс B (PID при эксперименте: 170).

-- 1. В опыте сеанс B имел PID 170 (отличался от PID 163 сеанса A).
SELECT pg_backend_pid();

-- 2. Потерянное обновление.
-- B2.1. После первого SELECT в A открыть транзакцию, прочитать 10.
BEGIN ISOLATION LEVEL READ COMMITTED;
SELECT qty FROM lab.inventory
WHERE product_id = (SELECT product_id FROM lab.lab12_targets WHERE target_code = 'P1');
-- ПАУЗА: A2.2 пишет константу qty=9, COMMIT.
-- B2.2. Повторно записать константу 9, вычисленную по старому значению 10.
UPDATE lab.inventory SET qty = 9
WHERE product_id = (SELECT product_id FROM lab.lab12_targets WHERE target_code = 'P1');
COMMIT;
-- Фактический итог P1=9 вместо 8.

-- 3. SELECT FOR UPDATE.
-- B3.1. После A3.1 попробовать заблокировать ту же строку.
BEGIN;
SELECT i.qty
FROM lab.inventory AS i
JOIN lab.lab12_targets AS t ON t.product_id = i.product_id
WHERE t.target_code = 'P1'
FOR UPDATE OF i;
-- ПАУЗА: запрос ЖДЁТ A3.2 и возобновляется с qty=9.
-- B3.2. После разблокировки списать ещё единицу.
UPDATE lab.inventory SET qty = qty - 1, version = version + 1
WHERE product_id = (SELECT product_id FROM lab.lab12_targets WHERE target_code = 'P1')
RETURNING qty;
COMMIT;
-- Фактический итог P1=8.

-- 4. Атомарное резервирование.
-- B4.1. После A4.1 начать транзакцию и выполнить UPDATE (ждать A4.2).
BEGIN;
UPDATE lab.inventory
SET qty = qty - 1, version = version + 1
WHERE product_id = (SELECT product_id FROM lab.lab12_targets WHERE target_code = 'P1')
  AND qty > 0
RETURNING qty;
-- ПАУЗА: A4.2 COMMIT. В B возвращается qty=8.
COMMIT;

-- 5. Неповторяемое чтение READ COMMITTED.
-- B5.1. После A5.1 поменять 10 на 7 и зафиксировать изменение.
BEGIN;
UPDATE lab.inventory SET qty = 7
WHERE product_id = (SELECT product_id FROM lab.lab12_targets WHERE target_code = 'P1');
COMMIT;
-- A5.2 читает 7 вместо 10.

-- 6. REPEATABLE READ.
-- B6.1. После A6.1 поменять 10 на 7 и зафиксировать изменение.
BEGIN;
UPDATE lab.inventory SET qty = 7
WHERE product_id = (SELECT product_id FROM lab.lab12_targets WHERE target_code = 'P1');
COMMIT;
-- A6.2 всё ещё читает 10, только после COMMIT A увидит 7.

-- 7. Фантомное чтение.
-- B7.1. После первого COUNT в A вставить отрицательное движение P1.
BEGIN;
INSERT INTO lab.inventory_movements (product_id, qty_delta)
SELECT product_id, -1 FROM lab.lab12_targets WHERE target_code = 'P1';
COMMIT;
-- A7.2 увидит COUNT=1 вместо 0.

-- 8. Deadlock.
-- B8.1. После A8.1 заблокировать P2.
BEGIN;
SELECT i.qty
FROM lab.inventory AS i
JOIN lab.lab12_targets AS t ON t.product_id = i.product_id
WHERE t.target_code = 'P2'
FOR UPDATE OF i;
-- ПАУЗА: A8.2 пытается получить P2 и ожидает.
-- B8.2. Теперь попытаться заблокировать P1, который удерживает A.
SELECT i.qty
FROM lab.inventory AS i
JOIN lab.lab12_targets AS t ON t.product_id = i.product_id
WHERE t.target_code = 'P1'
FOR UPDATE OF i;
-- ФАКТ: ERROR: deadlock detected. Сеанс B перешёл в состояние olist=!#.
-- B8.3. После ошибки выполнить:
ROLLBACK;
-- После освобождения блокировки A8.2 завершится, A сделает COMMIT.

-- 9*. SERIALIZABLE.
-- B9.1. После первого SELECT в A открыть SERIALIZABLE и прочитать P1/P2.
BEGIN ISOLATION LEVEL SERIALIZABLE;
SELECT t.target_code, i.qty
FROM lab.inventory AS i JOIN lab.lab12_targets AS t USING (product_id)
WHERE t.target_code IN ('P1','P2') ORDER BY t.target_code;
-- ПАУЗА: A9.2 обновляет P1 и выполняет COMMIT.
-- B9.2. UPDATE по старому снимку даст ошибку сериализации.
UPDATE lab.inventory
SET qty = qty - 1, version = version + 1
WHERE product_id = (SELECT product_id FROM lab.lab12_targets WHERE target_code = 'P1')
RETURNING qty;
-- ФАКТ: ERROR: could not serialize access due to concurrent update.
-- B9.3. Отменить старую транзакцию и повторить целиком.
ROLLBACK;
BEGIN ISOLATION LEVEL SERIALIZABLE;
UPDATE lab.inventory
SET qty = qty - 1, version = version + 1
WHERE product_id = (SELECT product_id FROM lab.lab12_targets WHERE target_code = 'P1')
  AND qty > 0
RETURNING qty;
COMMIT;
-- Фактический результат: qty=8, version=2.

-- 10. Восстановление данных производится один раз из A10 после всех опытов.
