-- Практическая работа № 14. EXPLAIN ANALYZE и оптимизация запросов.
-- Вариант 6. Фильтр после LEFT JOIN.
-- PostgreSQL 17, база olist, исходная схема olist.
-- Все запросы только читают данные Olist. Представления временные.
-- Выполнить в одном сеансе psql: два плана, EXCEPT и измерения.

\echo '=== 1. Проверка исходных данных ==='
SELECT COUNT(*) AS delivered_rj_orders
FROM olist.orders AS o
JOIN olist.customers AS c ON c.customer_id = o.customer_id
WHERE o.order_status = 'delivered' AND c.customer_state = 'RJ';

-- Предметная задача: для КАЖДОГО доставленного заказа покупателя из RJ
-- показать количество дорогих позиций (price >= 500 BRL) и их сумму
-- вместе с доставкой. Заказы без дорогих позиций должны сохраниться
-- (0 позиций, 0 BRL).

-- 2. Исходная менее эффективная форма: сначала LEFT JOIN ВСЕХ позиций,
-- потом условие цены применяется в агрегатах после соединения.
-- Применение WHERE oi.price >= 500 здесь было бы логической ошибкой:
-- оно исключило бы заказы, у которых нет дорогих позиций.
CREATE TEMP VIEW lab14_before AS
SELECT
    o.order_id,
    COUNT(oi.order_id) FILTER (WHERE oi.price >= 500) AS expensive_item_count,
    COALESCE(
        SUM(oi.price + oi.freight_value) FILTER (WHERE oi.price >= 500),
        0
    )::numeric(14, 2) AS expensive_total_brl
FROM olist.orders AS o
JOIN olist.customers AS c ON c.customer_id = o.customer_id
LEFT JOIN olist.order_items AS oi ON oi.order_id = o.order_id
WHERE o.order_status = 'delivered'
  AND c.customer_state = 'RJ'
GROUP BY o.order_id;

\echo '=== 2. Исходный запрос: EXPLAIN (ANALYZE, BUFFERS) ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM lab14_before ORDER BY order_id;

-- 3. Переписанный эквивалентный запрос: отбор позиций делается в ON
-- до агрегирования. LEFT JOIN сохраняет все нужные заказы.
CREATE TEMP VIEW lab14_after AS
SELECT
    o.order_id,
    COUNT(oi.order_id) AS expensive_item_count,
    COALESCE(SUM(oi.price + oi.freight_value), 0)::numeric(14, 2)
        AS expensive_total_brl
FROM olist.orders AS o
JOIN olist.customers AS c ON c.customer_id = o.customer_id
LEFT JOIN olist.order_items AS oi
    ON oi.order_id = o.order_id AND oi.price >= 500
WHERE o.order_status = 'delivered'
  AND c.customer_state = 'RJ'
GROUP BY o.order_id;

\echo '=== 3. Переписанный запрос: EXPLAIN (ANALYZE, BUFFERS) ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM lab14_after ORDER BY order_id;

-- 4. Доказательство эквивалентности: EXCEPT в обе стороны.
\echo '=== 4. Равенство результатов EXCEPT в обе стороны (ожидается 0 и 0) ==='
SELECT 'before_minus_after' AS check_name, COUNT(*) AS differing_rows
FROM (
    SELECT * FROM lab14_before
    EXCEPT
    SELECT * FROM lab14_after
) AS d
UNION ALL
SELECT 'after_minus_before', COUNT(*)
FROM (
    SELECT * FROM lab14_after
    EXCEPT
    SELECT * FROM lab14_before
) AS d;

\echo '=== 5. Контроль результатов ==='
SELECT 'before' AS variant, COUNT(*) AS orders_count,
       SUM(expensive_item_count) AS expensive_items,
       SUM(expensive_total_brl) AS expensive_sales_brl
FROM lab14_before
UNION ALL
SELECT 'after', COUNT(*), SUM(expensive_item_count), SUM(expensive_total_brl)
FROM lab14_after;

-- 6. Число строк, проходящих через JOIN до группировки.
-- Вариант до переноса фильтра в ON и после него.
\echo '=== 6. Размер промежуточного результата LEFT JOIN ==='
SELECT 'before' AS variant, COUNT(*) AS joined_rows
FROM olist.orders AS o
JOIN olist.customers AS c ON c.customer_id = o.customer_id
LEFT JOIN olist.order_items AS oi ON oi.order_id = o.order_id
WHERE o.order_status = 'delivered' AND c.customer_state = 'RJ'
UNION ALL
SELECT 'after', COUNT(*)
FROM olist.orders AS o
JOIN olist.customers AS c ON c.customer_id = o.customer_id
LEFT JOIN olist.order_items AS oi
    ON oi.order_id = o.order_id AND oi.price >= 500
WHERE o.order_status = 'delivered' AND c.customer_state = 'RJ';

-- 7. Демонстрация изменения семантики при ошибочном переносе
-- WHERE -> ON без сохранения логики. Не используется в EXCEPT
-- как оптимизированный вариант: запросы НАМЕРЕННО не эквивалентны.
\echo '=== 7. Почему WHERE oi.price >= 500 нельзя просто перенести в ON ==='
SELECT
    (SELECT COUNT(DISTINCT o.order_id)
     FROM olist.orders AS o
     JOIN olist.customers AS c ON c.customer_id = o.customer_id
     LEFT JOIN olist.order_items AS oi ON oi.order_id = o.order_id
     WHERE o.order_status = 'delivered'
       AND c.customer_state = 'RJ'
       AND oi.price >= 500) AS orders_with_where_filter,
    (SELECT COUNT(DISTINCT o.order_id)
     FROM olist.orders AS o
     JOIN olist.customers AS c ON c.customer_id = o.customer_id
     LEFT JOIN olist.order_items AS oi
       ON oi.order_id = o.order_id AND oi.price >= 500
     WHERE o.order_status = 'delivered'
       AND c.customer_state = 'RJ') AS orders_with_on_filter;

-- Нет тестовых индексов, изменения данных и постоянных объектов.
