-- Практическая работа № 9. Функциональные зависимости и нормализация
-- Студент: Кураева Екатерина Алексеевна
-- Группа: ИНБО-22-23
-- Вариант 6: delivery_flat
-- Исходные таблицы olist не изменяются.
-- Повторный запуск пересоздаёт только таблицы lab.nf_6_*.

BEGIN;
CREATE SCHEMA IF NOT EXISTS lab;

-- 1–6. Исходные функциональные зависимости, ключ и декомпозиция
-- (подробное обоснование приведено в README.md).
-- shipment_id -> order_id, seller_id
-- seller_id -> seller_city
-- event_code -> event_name
-- (shipment_id, attempt_no) -> attempt_time
-- Потенциальный ключ плоского отношения:
-- (shipment_id, attempt_no, event_code).
-- Итоговая декомпозиция соответствует НФБК и сохраняет перечисленные ФЗ.

-- 7. Реализация нормализованных отношений в схеме lab.
DROP TABLE IF EXISTS lab.nf_6_attempt_events;
DROP TABLE IF EXISTS lab.nf_6_attempts;
DROP TABLE IF EXISTS lab.nf_6_shipments;
DROP TABLE IF EXISTS lab.nf_6_event_types;
DROP TABLE IF EXISTS lab.nf_6_sellers;

CREATE TABLE lab.nf_6_sellers (
    seller_id text NOT NULL,
    seller_city text NOT NULL,
    CONSTRAINT pk_nf_6_sellers PRIMARY KEY (seller_id),
    CONSTRAINT fk_nf_6_sellers_olist FOREIGN KEY (seller_id)
        REFERENCES olist.sellers(seller_id)
);

CREATE TABLE lab.nf_6_shipments (
    shipment_id bigint NOT NULL,
    order_id text NOT NULL,
    seller_id text NOT NULL,
    CONSTRAINT pk_nf_6_shipments PRIMARY KEY (shipment_id),
    CONSTRAINT fk_nf_6_shipments_order FOREIGN KEY (order_id)
        REFERENCES olist.orders(order_id),
    CONSTRAINT fk_nf_6_shipments_seller FOREIGN KEY (seller_id)
        REFERENCES lab.nf_6_sellers(seller_id),
    CONSTRAINT uq_nf_6_shipments_order_seller UNIQUE (order_id, seller_id)
);

CREATE TABLE lab.nf_6_attempts (
    shipment_id bigint NOT NULL,
    attempt_no integer NOT NULL,
    attempt_time timestamp NOT NULL,
    CONSTRAINT pk_nf_6_attempts PRIMARY KEY (shipment_id, attempt_no),
    CONSTRAINT fk_nf_6_attempts_shipment FOREIGN KEY (shipment_id)
        REFERENCES lab.nf_6_shipments(shipment_id),
    CONSTRAINT ck_nf_6_attempts_no CHECK (attempt_no > 0)
);

CREATE TABLE lab.nf_6_event_types (
    event_code text NOT NULL,
    event_name text NOT NULL,
    CONSTRAINT pk_nf_6_event_types PRIMARY KEY (event_code),
    CONSTRAINT uq_nf_6_event_types_name UNIQUE (event_name)
);

CREATE TABLE lab.nf_6_attempt_events (
    shipment_id bigint NOT NULL,
    attempt_no integer NOT NULL,
    event_code text NOT NULL,
    CONSTRAINT pk_nf_6_attempt_events
        PRIMARY KEY (shipment_id, attempt_no, event_code),
    CONSTRAINT fk_nf_6_events_attempt FOREIGN KEY (shipment_id, attempt_no)
        REFERENCES lab.nf_6_attempts(shipment_id, attempt_no),
    CONSTRAINT fk_nf_6_events_type FOREIGN KEY (event_code)
        REFERENCES lab.nf_6_event_types(event_code)
);

-- 8. Подготовка плоского набора из реальных идентификаторов Olist.
-- Выбираются 3 продавца (2 + 2 + 1 заказа); события и время попыток
-- учебные и не претендуют на фактическую историю доставки Olist.
DROP TABLE IF EXISTS pg_temp.lab09_flat;
CREATE TEMP TABLE lab09_flat ON COMMIT DROP AS
WITH eligible_sellers AS (
    SELECT oi.seller_id,
           ROW_NUMBER() OVER (ORDER BY oi.seller_id) AS seller_rank
    FROM olist.order_items AS oi
    JOIN olist.orders AS o ON o.order_id = oi.order_id
    JOIN olist.sellers AS s ON s.seller_id = oi.seller_id
    WHERE o.order_status = 'delivered'
      AND s.seller_city IS NOT NULL
    GROUP BY oi.seller_id
    HAVING COUNT(DISTINCT oi.order_id) >= 2
    ORDER BY oi.seller_id
    LIMIT 3
),
ranked_orders AS (
    SELECT es.seller_rank, es.seller_id, oi.order_id,
           ROW_NUMBER() OVER (
               PARTITION BY es.seller_id ORDER BY oi.order_id
           ) AS order_rank
    FROM eligible_sellers AS es
    JOIN (
        SELECT DISTINCT oi.seller_id, oi.order_id
        FROM olist.order_items AS oi
        JOIN olist.orders AS o ON o.order_id = oi.order_id
        WHERE o.order_status = 'delivered'
    ) AS oi ON oi.seller_id = es.seller_id
),
selected_orders AS (
    SELECT seller_id, order_id
    FROM ranked_orders
    WHERE (seller_rank IN (1, 2) AND order_rank <= 2)
       OR (seller_rank = 3 AND order_rank = 1)
),
numbered AS (
    SELECT ROW_NUMBER() OVER (ORDER BY seller_id, order_id)::bigint
               AS shipment_id,
           order_id, seller_id
    FROM selected_orders
)
SELECT n.shipment_id,
       n.order_id,
       n.seller_id,
       s.seller_city,
       1::integer AS attempt_no,
       (o.order_purchase_timestamp + INTERVAL '1 day')::timestamp
           AS attempt_time,
       CASE (n.shipment_id % 3)
           WHEN 0 THEN 'DELIVERED'
           WHEN 1 THEN 'IN_TRANSIT'
           ELSE 'ATTEMPTED'
       END::text AS event_code,
       CASE (n.shipment_id % 3)
           WHEN 0 THEN 'Доставлено'
           WHEN 1 THEN 'В пути'
           ELSE 'Попытка доставки'
       END::text AS event_name
FROM numbered AS n
JOIN olist.sellers AS s ON s.seller_id = n.seller_id
JOIN olist.orders AS o ON o.order_id = n.order_id;

-- Справочные значения теперь записываются по одному разу.
INSERT INTO lab.nf_6_sellers (seller_id, seller_city)
SELECT DISTINCT seller_id, seller_city FROM lab09_flat;

INSERT INTO lab.nf_6_shipments (shipment_id, order_id, seller_id)
SELECT DISTINCT shipment_id, order_id, seller_id FROM lab09_flat;

INSERT INTO lab.nf_6_attempts (shipment_id, attempt_no, attempt_time)
SELECT DISTINCT shipment_id, attempt_no, attempt_time FROM lab09_flat;

INSERT INTO lab.nf_6_event_types (event_code, event_name)
SELECT DISTINCT event_code, event_name FROM lab09_flat;

INSERT INTO lab.nf_6_attempt_events (shipment_id, attempt_no, event_code)
SELECT DISTINCT shipment_id, attempt_no, event_code FROM lab09_flat;

-- Количество строк в исходной плоской и новых таблицах.
SELECT 'delivery_flat' AS table_name, COUNT(*) AS row_count FROM lab09_flat
UNION ALL SELECT 'nf_6_sellers', COUNT(*) FROM lab.nf_6_sellers
UNION ALL SELECT 'nf_6_shipments', COUNT(*) FROM lab.nf_6_shipments
UNION ALL SELECT 'nf_6_attempts', COUNT(*) FROM lab.nf_6_attempts
UNION ALL SELECT 'nf_6_event_types', COUNT(*) FROM lab.nf_6_event_types
UNION ALL SELECT 'nf_6_attempt_events', COUNT(*) FROM lab.nf_6_attempt_events
ORDER BY table_name;

-- Сравнение повторов справочных данных до и после нормализации.
SELECT 'seller_city_in_flat' AS metric, COUNT(*) AS occurrences
FROM lab09_flat
UNION ALL SELECT 'seller_city_in_reference', COUNT(*)
FROM lab.nf_6_sellers
UNION ALL SELECT 'event_name_in_flat', COUNT(*) FROM lab09_flat
UNION ALL SELECT 'event_name_in_reference', COUNT(*)
FROM lab.nf_6_event_types
ORDER BY metric;

-- Проверка соединения без потерь: обе разности должны быть пустыми.
WITH reconstructed AS (
    SELECT sh.shipment_id, sh.order_id, sh.seller_id, se.seller_city,
           at.attempt_no, at.attempt_time, ev.event_code, et.event_name
    FROM lab.nf_6_attempt_events AS ev
    JOIN lab.nf_6_attempts AS at
      ON at.shipment_id = ev.shipment_id
     AND at.attempt_no = ev.attempt_no
    JOIN lab.nf_6_shipments AS sh
      ON sh.shipment_id = at.shipment_id
    JOIN lab.nf_6_sellers AS se
      ON se.seller_id = sh.seller_id
    JOIN lab.nf_6_event_types AS et
      ON et.event_code = ev.event_code
),
flat_minus_reconstructed AS (
    SELECT * FROM lab09_flat EXCEPT SELECT * FROM reconstructed
),
reconstructed_minus_flat AS (
    SELECT * FROM reconstructed EXCEPT SELECT * FROM lab09_flat
)
SELECT 'flat_minus_reconstructed' AS comparison,
       COUNT(*) AS differing_rows FROM flat_minus_reconstructed
UNION ALL
SELECT 'reconstructed_minus_flat', COUNT(*)
FROM reconstructed_minus_flat;

-- Просмотр нормализованных данных после соединения.
SELECT sh.shipment_id, sh.order_id, sh.seller_id, se.seller_city,
       at.attempt_no, at.attempt_time, ev.event_code, et.event_name
FROM lab.nf_6_attempt_events AS ev
JOIN lab.nf_6_attempts AS at
  ON at.shipment_id = ev.shipment_id AND at.attempt_no = ev.attempt_no
JOIN lab.nf_6_shipments AS sh ON sh.shipment_id = at.shipment_id
JOIN lab.nf_6_sellers AS se ON se.seller_id = sh.seller_id
JOIN lab.nf_6_event_types AS et ON et.event_code = ev.event_code
ORDER BY sh.shipment_id, at.attempt_no, ev.event_code;

-- Проверка именованных PK, FK, UNIQUE и CHECK в созданных таблицах.
SELECT tc.table_name, tc.constraint_name, tc.constraint_type
FROM information_schema.table_constraints AS tc
WHERE tc.table_schema = 'lab'
  AND tc.table_name LIKE 'nf_6_%'
  AND tc.constraint_type IN ('PRIMARY KEY', 'FOREIGN KEY', 'UNIQUE', 'CHECK')
  AND tc.constraint_name !~ '^[0-9]+_'
ORDER BY tc.table_name, tc.constraint_type, tc.constraint_name;

-- Ошибочные операции (не выполняются):
-- 1. Повтор ключа отправления: нарушение pk_nf_6_shipments.
-- INSERT INTO lab.nf_6_shipments
-- SELECT shipment_id, order_id, seller_id
-- FROM lab.nf_6_shipments WHERE shipment_id = 1;
-- 2. Несуществующая попытка: нарушение fk_nf_6_events_attempt.
-- INSERT INTO lab.nf_6_attempt_events VALUES (999, 1, 'DELIVERED');
-- 3. Нулевой номер попытки: нарушение ck_nf_6_attempts_no.
-- INSERT INTO lab.nf_6_attempts VALUES (1, 0, CURRENT_TIMESTAMP);

COMMIT;
