-- Практическая работа № 8. ER-модель и расширение предметной области
-- Студент: Кураева Екатерина Алексеевна
-- Группа: ИНБО-22-23
-- Вариант 6: попытки доставки
-- СУБД: PostgreSQL 17; база olist
-- Создаются только учебные таблицы схемы lab.

CREATE SCHEMA IF NOT EXISTS lab;

-- 1–4. Таблицы, первичные и внешние ключи, ограничения.
-- Повторный запуск пересоздаёт только три учебные таблицы lab08.
DROP TABLE IF EXISTS lab.delivery_events;
DROP TABLE IF EXISTS lab.delivery_attempts;
DROP TABLE IF EXISTS lab.shipments;

-- Отправление связано с заказом и продавцом Olist.
CREATE TABLE lab.shipments (
    shipment_id bigint GENERATED ALWAYS AS IDENTITY,
    order_id text NOT NULL,
    seller_id text NOT NULL,
    tracking_code text NOT NULL,
    shipment_status text NOT NULL,
    created_at timestamp NOT NULL,
    delivered_at timestamp,
    CONSTRAINT pk_shipments PRIMARY KEY (shipment_id),
    CONSTRAINT uq_shipments_tracking_code UNIQUE (tracking_code),
    CONSTRAINT uq_shipments_order_seller UNIQUE (order_id, seller_id),
    CONSTRAINT uq_shipments_id_order UNIQUE (shipment_id, order_id),
    CONSTRAINT fk_shipments_order FOREIGN KEY (order_id)
        REFERENCES olist.orders (order_id),
    CONSTRAINT fk_shipments_seller FOREIGN KEY (seller_id)
        REFERENCES olist.sellers (seller_id),
    CONSTRAINT ck_shipments_status CHECK (
        shipment_status IN ('created', 'in_transit', 'delivered', 'returned')
    ),
    CONSTRAINT ck_shipments_delivery_time CHECK (
        delivered_at IS NULL OR delivered_at >= created_at
    ),
    CONSTRAINT ck_shipments_delivered_date CHECK (
        shipment_status <> 'delivered' OR delivered_at IS NOT NULL
    )
);

-- Попытки доставки: несколько попыток могут относиться к одному отправлению.
-- Составной FK гарантирует, что order_id совпадает с заказом отправления.
CREATE TABLE lab.delivery_attempts (
    attempt_id bigint GENERATED ALWAYS AS IDENTITY,
    shipment_id bigint NOT NULL,
    order_id text NOT NULL,
    attempt_no integer NOT NULL,
    attempted_at timestamp NOT NULL,
    attempt_result text NOT NULL,
    CONSTRAINT pk_delivery_attempts PRIMARY KEY (attempt_id),
    CONSTRAINT uq_attempts_shipment_number UNIQUE (shipment_id, attempt_no),
    CONSTRAINT uq_attempts_id_shipment UNIQUE (attempt_id, shipment_id),
    CONSTRAINT fk_attempts_shipment_order FOREIGN KEY (shipment_id, order_id)
        REFERENCES lab.shipments (shipment_id, order_id),
    CONSTRAINT fk_attempts_order FOREIGN KEY (order_id)
        REFERENCES olist.orders (order_id),
    CONSTRAINT ck_attempts_number CHECK (attempt_no >= 1),
    CONSTRAINT ck_attempts_result CHECK (
        attempt_result IN ('success', 'customer_absent', 'address_issue', 'other_failure')
    )
);

-- События попыток: одной попытке соответствует несколько событий.
-- Составной FK не позволяет связать событие с чужим отправлением.
CREATE TABLE lab.delivery_events (
    event_id bigint GENERATED ALWAYS AS IDENTITY,
    shipment_id bigint NOT NULL,
    attempt_id bigint NOT NULL,
    event_type text NOT NULL,
    event_at timestamp NOT NULL,
    event_note text,
    CONSTRAINT pk_delivery_events PRIMARY KEY (event_id),
    CONSTRAINT fk_events_attempt_shipment FOREIGN KEY (attempt_id, shipment_id)
        REFERENCES lab.delivery_attempts (attempt_id, shipment_id),
    CONSTRAINT ck_events_type CHECK (
        event_type IN ('out_for_delivery', 'delivery_confirmed',
                       'delivery_failed', 'recipient_notified')
    )
);

-- 5. Тестовые данные: пять реальных пар order_id/seller_id из Olist.
-- История попыток и событий является учебной моделью, а не реальным
-- журналом перевозчика. Времена доставки берутся из заказов Olist.
WITH selected AS (
    SELECT order_id, seller_id, purchase_time, delivery_time,
           ROW_NUMBER() OVER (ORDER BY order_id, seller_id) AS n
    FROM (
        SELECT DISTINCT
            o.order_id, oi.seller_id,
            o.order_purchase_timestamp AS purchase_time,
            o.order_delivered_customer_date AS delivery_time
        FROM olist.orders AS o
        JOIN olist.order_items AS oi ON oi.order_id = o.order_id
        WHERE o.order_status = 'delivered'
          AND o.order_purchase_timestamp IS NOT NULL
          AND o.order_delivered_customer_date IS NOT NULL
          AND o.order_delivered_customer_date >= o.order_purchase_timestamp
    ) AS pairs
    ORDER BY order_id, seller_id
    LIMIT 5
)
INSERT INTO lab.shipments
    (order_id, seller_id, tracking_code, shipment_status, created_at, delivered_at)
SELECT order_id, seller_id, 'LAB08-' || LPAD(n::text, 3, '0'),
       'delivered', purchase_time, delivery_time
FROM selected;

INSERT INTO lab.delivery_attempts
    (shipment_id, order_id, attempt_no, attempted_at, attempt_result)
SELECT shipment_id, order_id, 1, delivered_at, 'success'
FROM lab.shipments;

INSERT INTO lab.delivery_events
    (shipment_id, attempt_id, event_type, event_at, event_note)
SELECT a.shipment_id, a.attempt_id, 'delivery_confirmed',
       a.attempted_at, 'Учебная запись о подтверждении доставки'
FROM lab.delivery_attempts AS a;

-- Контроль наполнения: ожидается не менее пяти строк в каждой таблице.
SELECT 'shipments' AS table_name, COUNT(*) AS row_count FROM lab.shipments
UNION ALL
SELECT 'delivery_attempts', COUNT(*) FROM lab.delivery_attempts
UNION ALL
SELECT 'delivery_events', COUNT(*) FROM lab.delivery_events
ORDER BY table_name;

-- Пример связанного результата (заказ -> отправление -> попытка -> событие).
SELECT s.order_id, s.seller_id, s.tracking_code,
       a.attempt_no, a.attempt_result, e.event_type, e.event_at
FROM lab.shipments AS s
JOIN lab.delivery_attempts AS a ON a.shipment_id = s.shipment_id
JOIN lab.delivery_events AS e ON e.attempt_id = a.attempt_id
ORDER BY s.shipment_id, a.attempt_no, e.event_at;

-- 6. Примеры ошибочных операций (не исполняются).
-- Ошибка FK: такого заказа нет в исходной olist.orders.
-- INSERT INTO lab.shipments
-- (order_id, seller_id, tracking_code, shipment_status, created_at)
-- VALUES ('UNKNOWN_ORDER', 'UNKNOWN_SELLER', 'BAD-01', 'created', NOW());
-- Ограничение: fk_shipments_order (также нарушится fk_shipments_seller).

-- Ошибка CHECK: номер попытки должен быть положительным.
-- UPDATE lab.delivery_attempts SET attempt_no = 0 WHERE attempt_id = 1;
-- Ограничение: ck_attempts_number.

-- Ошибка UNIQUE: повторение кода отслеживания.
-- UPDATE lab.shipments SET tracking_code = 'LAB08-001'
-- WHERE tracking_code = 'LAB08-002';
-- Ограничение: uq_shipments_tracking_code.

-- Ошибка CHECK: статус delivered требует заполненной даты доставки.
-- UPDATE lab.shipments SET delivered_at = NULL
-- WHERE tracking_code = 'LAB08-001';
-- Ограничение: ck_shipments_delivered_date.

-- 7. Проверка структуры через системный каталог PostgreSQL.
SELECT tc.table_name, tc.constraint_name, tc.constraint_type
FROM information_schema.table_constraints AS tc
WHERE tc.table_schema = 'lab'
  AND tc.table_name IN ('shipments', 'delivery_attempts', 'delivery_events')
ORDER BY tc.table_name, tc.constraint_type, tc.constraint_name;

-- Проверка объявленных NOT NULL.
SELECT table_name, column_name, is_nullable
FROM information_schema.columns
WHERE table_schema = 'lab'
  AND table_name IN ('shipments', 'delivery_attempts', 'delivery_events')
ORDER BY table_name, ordinal_position;

-- Контроль соответствия внешних ключей существующим объектам.
SELECT 'shipments_without_order' AS check_name, COUNT(*) AS violations
FROM lab.shipments AS s
LEFT JOIN olist.orders AS o ON o.order_id = s.order_id
WHERE o.order_id IS NULL
UNION ALL
SELECT 'shipments_without_seller', COUNT(*)
FROM lab.shipments AS s
LEFT JOIN olist.sellers AS sl ON sl.seller_id = s.seller_id
WHERE sl.seller_id IS NULL
UNION ALL
SELECT 'attempts_without_shipment', COUNT(*)
FROM lab.delivery_attempts AS a
LEFT JOIN lab.shipments AS s
    ON s.shipment_id = a.shipment_id AND s.order_id = a.order_id
WHERE s.shipment_id IS NULL
UNION ALL
SELECT 'events_without_attempt', COUNT(*)
FROM lab.delivery_events AS e
LEFT JOIN lab.delivery_attempts AS a
    ON a.attempt_id = e.attempt_id AND a.shipment_id = e.shipment_id
WHERE a.attempt_id IS NULL
ORDER BY check_name;
