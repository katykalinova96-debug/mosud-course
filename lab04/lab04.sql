-- Практическая работа № 4. Соединения отношений и сложные JOIN
-- Студент: Кураева Екатерина Алексеевна
-- Группа: ИНБО-22-23
-- Вариант: 6. Повторные покупатели
-- Исходные данные Olist не изменяются.

-- 1. Основной запрос: повторные покупатели и даты первой/последней покупки.
-- customers -> orders: для одного customer_id соответствует не более одного клиента (N:1 со стороны orders).
-- orders -> order_items: одному заказу соответствует 0..N позиций.
-- Сначала считаем позиции для каждого заказа, чтобы не размножать заказы.
-- LEFT JOIN сохраняет заказ, даже если в нем нет позиций.
WITH items_by_order AS (
    SELECT order_id, COUNT(*) AS item_count
    FROM olist.order_items
    GROUP BY order_id
),
customer_orders AS (
    SELECT c.customer_unique_id,
           o.order_id,
           o.order_purchase_timestamp,
           COALESCE(i.item_count, 0) AS item_count
    FROM olist.customers AS c
    JOIN olist.orders AS o ON o.customer_id = c.customer_id
    LEFT JOIN items_by_order AS i ON i.order_id = o.order_id
    WHERE c.customer_unique_id IS NOT NULL
      AND o.order_purchase_timestamp IS NOT NULL
)
SELECT customer_unique_id,
       COUNT(*) AS orders_count,
       MIN(order_purchase_timestamp) AS first_purchase,
       MAX(order_purchase_timestamp) AS last_purchase,
       MAX(order_purchase_timestamp) - MIN(order_purchase_timestamp) AS period_between_purchases,
       SUM(item_count) AS total_items
FROM customer_orders
GROUP BY customer_unique_id
HAVING COUNT(*) >= 2
ORDER BY orders_count DESC, customer_unique_id
LIMIT 15;

-- 2. Общая статистика по повторным покупателям (без LIMIT).
WITH purchase_counts AS (
    SELECT c.customer_unique_id,
           COUNT(*) AS orders_count,
           MIN(o.order_purchase_timestamp) AS first_purchase,
           MAX(o.order_purchase_timestamp) AS last_purchase
    FROM olist.customers AS c
    JOIN olist.orders AS o ON o.customer_id = c.customer_id
    WHERE c.customer_unique_id IS NOT NULL
      AND o.order_purchase_timestamp IS NOT NULL
    GROUP BY c.customer_unique_id
)
SELECT COUNT(*) FILTER (WHERE orders_count >= 2) AS repeat_customers,
       COUNT(*) AS all_unique_customers_with_purchases,
       MAX(orders_count) AS maximum_orders_per_customer
FROM purchase_counts;

-- 3. LEFT JOIN: сохраняем все заказы, включая заказы без позиций.
SELECT COUNT(*) AS all_orders,
       COUNT(*) FILTER (WHERE i.order_id IS NULL) AS orders_without_items
FROM olist.orders AS o
LEFT JOIN (
    SELECT DISTINCT order_id FROM olist.order_items
) AS i ON i.order_id = o.order_id;

-- 4. Антисоединение: заказы, для которых отсутствует отзыв.
-- NOT EXISTS проверяет отсутствие связанных строк, не размножая результат.
SELECT COUNT(*) AS orders_without_reviews
FROM olist.orders AS o
WHERE NOT EXISTS (
    SELECT 1
    FROM olist.order_reviews AS r
    WHERE r.order_id = o.order_id
);

-- 5. Намеренно ошибочный JOIN: заказ может иметь несколько позиций и платежей.
-- Если напрямую соединить обе таблицы по order_id, каждый платеж повторится
-- столько раз, сколько в данном заказе позиций. SUM(payment_value) будет завышена.
WITH incorrect AS (
    SELECT SUM(p.payment_value) AS inflated_payment_sum,
           COUNT(*) AS joined_rows
    FROM olist.orders AS o
    JOIN olist.order_items AS i ON i.order_id = o.order_id
    JOIN olist.order_payments AS p ON p.order_id = o.order_id
),
correct AS (
    SELECT SUM(p.payment_value) AS correct_payment_sum,
           COUNT(*) AS payment_rows
    FROM olist.orders AS o
    JOIN olist.order_payments AS p ON p.order_id = o.order_id
    WHERE EXISTS (
        SELECT 1 FROM olist.order_items AS i WHERE i.order_id = o.order_id
    )
)
SELECT incorrect.joined_rows,
       correct.payment_rows,
       incorrect.inflated_payment_sum,
       correct.correct_payment_sum,
       incorrect.inflated_payment_sum - correct.correct_payment_sum AS overstatement
FROM incorrect CROSS JOIN correct;

-- 6. Исправление: предварительная агрегация позиций и платежей по order_id.
-- Теперь каждому order_id соответствует не более одной строки в каждом CTE.
WITH items_by_order AS (
    SELECT order_id, COUNT(*) AS item_count, SUM(price) AS items_value
    FROM olist.order_items
    GROUP BY order_id
),
payments_by_order AS (
    SELECT order_id, COUNT(*) AS payment_count, SUM(payment_value) AS payment_sum
    FROM olist.order_payments
    GROUP BY order_id
)
SELECT COUNT(*) AS orders_with_items_and_payments,
       SUM(i.item_count) AS items_count,
       SUM(p.payment_count) AS payments_count,
       SUM(i.items_value) AS items_total,
       SUM(p.payment_sum) AS payments_total
FROM olist.orders AS o
JOIN items_by_order AS i ON i.order_id = o.order_id
JOIN payments_by_order AS p ON p.order_id = o.order_id;

-- 7. Контроль: сумма платежей из исправленного соединения равна
-- сумме платежей без размножения для заказов с позициями.
WITH items_by_order AS (
    SELECT DISTINCT order_id FROM olist.order_items
),
payments_by_order AS (
    SELECT order_id, SUM(payment_value) AS payment_sum
    FROM olist.order_payments
    GROUP BY order_id
),
expected AS (
    SELECT SUM(p.payment_value) AS payment_sum
    FROM olist.order_payments AS p
    WHERE EXISTS (SELECT 1 FROM olist.order_items AS i WHERE i.order_id = p.order_id)
),
actual AS (
    SELECT SUM(p.payment_sum) AS payment_sum
    FROM items_by_order AS i
    JOIN payments_by_order AS p ON p.order_id = i.order_id
)
SELECT expected.payment_sum AS expected_payment_sum,
       actual.payment_sum AS actual_payment_sum,
       expected.payment_sum IS NOT DISTINCT FROM actual.payment_sum AS sums_match
FROM expected CROSS JOIN actual;

-- 8. Композиция операций реляционной алгебры и кратности связей
-- подробно приведены в lab04/README.md.
