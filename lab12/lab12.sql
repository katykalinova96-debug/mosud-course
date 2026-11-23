-- Практическая работа № 12. Транзакции, конкурентный доступ и блокировки
-- Кураева Екатерина Алексеевна, ИНБО-22-23
-- PostgreSQL 17, база olist. Подготовка к экспериментам в двух сеансах.
-- ВНИМАНИЕ: при повторном запуске пересоздаются ТОЛЬКО
-- lab.inventory_movements, lab.lab12_targets и lab.inventory.
-- Запускайте этот файл ОДИН РАЗ до экспериментов A/B.

\set ON_ERROR_STOP on
CREATE SCHEMA IF NOT EXISTS lab;

DROP TABLE IF EXISTS lab.inventory_movements;
DROP TABLE IF EXISTS lab.lab12_targets;
DROP TABLE IF EXISTS lab.inventory;

CREATE TABLE lab.inventory (
    product_id text CONSTRAINT pk_lab12_inventory PRIMARY KEY
        REFERENCES olist.products(product_id),
    qty integer NOT NULL CONSTRAINT ck_lab12_inventory_qty CHECK (qty >= 0),
    version integer NOT NULL DEFAULT 0
        CONSTRAINT ck_lab12_inventory_version CHECK (version >= 0)
);

-- Журнал учебных движений: используется в эксперименте с фантомным чтением.
CREATE TABLE lab.inventory_movements (
    movement_id bigint GENERATED ALWAYS AS IDENTITY
        CONSTRAINT pk_lab12_movements PRIMARY KEY,
    product_id text NOT NULL
        CONSTRAINT fk_lab12_movements_product REFERENCES lab.inventory(product_id),
    qty_delta integer NOT NULL
        CONSTRAINT ck_lab12_movements_delta CHECK (qty_delta <> 0),
    created_at timestamp NOT NULL DEFAULT clock_timestamp()
);

-- Фиксируем два идентификатора для всех последующих экспериментов.
CREATE TABLE lab.lab12_targets (
    target_code text CONSTRAINT pk_lab12_targets PRIMARY KEY
        CONSTRAINT ck_lab12_targets_code CHECK (target_code IN ('P1', 'P2')),
    product_id text NOT NULL UNIQUE
        CONSTRAINT fk_lab12_targets_product REFERENCES lab.inventory(product_id)
);

-- Реальные product_id из Olist; все остатки изначально равны 10.
INSERT INTO lab.inventory (product_id, qty)
SELECT oi.product_id, 10
FROM olist.order_items AS oi
WHERE oi.product_id IS NOT NULL
GROUP BY oi.product_id
ORDER BY COUNT(*) DESC, oi.product_id
LIMIT 100;

INSERT INTO lab.lab12_targets (target_code, product_id)
SELECT CASE WHEN rn = 1 THEN 'P1' ELSE 'P2' END, product_id
FROM (
    SELECT product_id, ROW_NUMBER() OVER (ORDER BY product_id) AS rn
    FROM lab.inventory
    ORDER BY product_id
    LIMIT 2
) AS t;

-- Проверка двух выбранных товаров и общего наполнения.
SELECT t.target_code, t.product_id, i.qty, i.version
FROM lab.lab12_targets AS t
JOIN lab.inventory AS i ON i.product_id = t.product_id
ORDER BY t.target_code;

SELECT COUNT(*) AS inventory_rows,
       MIN(qty) AS min_qty,
       MAX(qty) AS max_qty
FROM lab.inventory;

-- Атомарное резервирование одной единицы (задание 4).
-- ROLLBACK восстанавливает qty=10 для двухсеансовых экспериментов.
BEGIN;
UPDATE lab.inventory
SET qty = qty - 1,
    version = version + 1
WHERE product_id = (SELECT product_id FROM lab.lab12_targets WHERE target_code = 'P1')
  AND qty > 0
RETURNING product_id, qty AS qty_after_reservation, version;
ROLLBACK;

SELECT t.target_code, i.qty AS qty_after_rollback
FROM lab.lab12_targets AS t
JOIN lab.inventory AS i ON i.product_id = t.product_id
WHERE t.target_code = 'P1';

-- Следующий этап: ДВА независимых окна psql, инструкции в session_a.sql/session_b.sql.
