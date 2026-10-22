-- Практическая работа № 5. Кванторы, EXISTS и реляционное деление
-- Студент: Кураева Екатерина Алексеевна
-- Группа: ИНБО-22-23
-- Вариант 6: PA, AM, RO
-- Учитываются только заказы со статусом delivered, NULL-категории исключены.
-- Исходные таблицы схемы olist не изменяются.

-- 1. Множество обязательных штатов S.
CREATE TEMP TABLE target_states (state text PRIMARY KEY) ON COMMIT PRESERVE ROWS;
INSERT INTO target_states (state) VALUES ('PA'), ('AM'), ('RO');

-- Материализация данных один раз вместо повторной обработки VIEW.
-- Оставляем уникальные пары категория--штат и продавец--штат.
CREATE TEMP TABLE lab05_sales AS
SELECT DISTINCT p.product_category_name, c.customer_state, oi.seller_id, o.order_id
FROM olist.customers AS c
JOIN olist.orders AS o ON o.customer_id = c.customer_id
JOIN olist.order_items AS oi ON oi.order_id = o.order_id
JOIN olist.products AS p ON p.product_id = oi.product_id
WHERE o.order_status = 'delivered'
  AND p.product_category_name IS NOT NULL
  AND c.customer_state IN (SELECT state FROM target_states);

CREATE TEMP TABLE lab05_category_states AS
SELECT DISTINCT product_category_name, customer_state
FROM lab05_sales;

CREATE TEMP TABLE lab05_seller_states AS
SELECT DISTINCT seller_id, customer_state
FROM lab05_sales;

ANALYZE lab05_sales;
ANALYZE lab05_category_states;
ANALYZE lab05_seller_states;

-- Кандидаты из всех существующих ненулевых категорий каталога.
CREATE TEMP TABLE lab05_candidates AS
SELECT DISTINCT product_category_name
FROM olist.products
WHERE product_category_name IS NOT NULL;

-- 2. Двойной NOT EXISTS: нет штата S без продажи данной категории.
CREATE TEMP TABLE lab05_by_not_exists AS
SELECT c.product_category_name
FROM lab05_candidates AS c
WHERE NOT EXISTS (
  SELECT 1 FROM target_states AS t
  WHERE NOT EXISTS (
    SELECT 1 FROM lab05_category_states AS s
    WHERE s.product_category_name = c.product_category_name
      AND s.customer_state = t.state
  )
);

-- 3. GROUP BY / HAVING COUNT(DISTINCT state).
-- Для пустого S добавлена отдельная ветка универсальной истинности.
CREATE TEMP TABLE lab05_by_having AS
SELECT c.product_category_name
FROM lab05_candidates AS c
WHERE NOT EXISTS (SELECT 1 FROM target_states)
UNION
SELECT s.product_category_name
FROM lab05_category_states AS s
JOIN target_states AS t ON t.state = s.customer_state
GROUP BY s.product_category_name
HAVING COUNT(DISTINCT s.customer_state) = (SELECT COUNT(*) FROM target_states);

-- 4. EXCEPT + NOT EXISTS: нет обязательного штата, отсутствующего в продажах.
CREATE TEMP TABLE lab05_by_except AS
SELECT c.product_category_name
FROM lab05_candidates AS c
WHERE NOT EXISTS (
  SELECT state FROM target_states
  EXCEPT
  SELECT s.customer_state FROM lab05_category_states AS s
  WHERE s.product_category_name = c.product_category_name
);

-- Сравнение мощностей трёх результатов.
SELECT 'double_not_exists' AS method, count(*) AS category_count FROM lab05_by_not_exists
UNION ALL SELECT 'group_by_having', count(*) FROM lab05_by_having
UNION ALL SELECT 'except_not_exists', count(*) FROM lab05_by_except
ORDER BY method;

-- Пример найденных категорий (не более 20).
SELECT product_category_name FROM lab05_by_not_exists
ORDER BY product_category_name LIMIT 20;

-- 5. Проверка попарной эквивалентности операцией EXCEPT в обе стороны.
-- Во всех шести строках должно быть 0.
SELECT 'not_exists - having' AS comparison, count(*) AS differing_categories FROM
 (SELECT product_category_name FROM lab05_by_not_exists EXCEPT SELECT product_category_name FROM lab05_by_having) AS q
UNION ALL SELECT 'having - not_exists', count(*) FROM
 (SELECT product_category_name FROM lab05_by_having EXCEPT SELECT product_category_name FROM lab05_by_not_exists) AS q
UNION ALL SELECT 'not_exists - except', count(*) FROM
 (SELECT product_category_name FROM lab05_by_not_exists EXCEPT SELECT product_category_name FROM lab05_by_except) AS q
UNION ALL SELECT 'except - not_exists', count(*) FROM
 (SELECT product_category_name FROM lab05_by_except EXCEPT SELECT product_category_name FROM lab05_by_not_exists) AS q
UNION ALL SELECT 'having - except', count(*) FROM
 (SELECT product_category_name FROM lab05_by_having EXCEPT SELECT product_category_name FROM lab05_by_except) AS q
UNION ALL SELECT 'except - having', count(*) FROM
 (SELECT product_category_name FROM lab05_by_except EXCEPT SELECT product_category_name FROM lab05_by_having) AS q
ORDER BY comparison;

-- 6. Диагностика: одна найденная категория, штаты S, число уникальных доставленных заказов.
WITH chosen AS (
  SELECT product_category_name FROM lab05_by_not_exists
  ORDER BY product_category_name LIMIT 1
)
SELECT ch.product_category_name, t.state AS customer_state,
       COUNT(DISTINCT s.order_id) AS delivered_orders
FROM chosen AS ch
CROSS JOIN target_states AS t
LEFT JOIN lab05_sales AS s
 ON s.product_category_name = ch.product_category_name
 AND s.customer_state = t.state
GROUP BY ch.product_category_name, t.state
ORDER BY t.state;

-- 7. Пустое S: условие «для каждого штата S» истинно для любой
-- существующей ненулевой категории (вакуумная истинность).
WITH empty_target_states(state) AS (SELECT NULL::text WHERE false)
SELECT (SELECT COUNT(*) FROM empty_target_states) AS required_states,
       (SELECT COUNT(*) FROM lab05_candidates) AS candidate_categories,
       (SELECT COUNT(*) FROM lab05_candidates AS c
        WHERE NOT EXISTS (
          SELECT 1 FROM empty_target_states AS t
          WHERE NOT EXISTS (
            SELECT 1 FROM lab05_category_states AS s
            WHERE s.product_category_name = c.product_category_name
              AND s.customer_state = t.state
          )
        )) AS categories_satisfying_empty_s;

-- 8. Дополнительно: продавцы, продававшие покупателям во всех штатах S.
WITH qualifying_sellers AS (
 SELECT DISTINCT s.seller_id
 FROM lab05_seller_states AS s
 WHERE NOT EXISTS (
   SELECT 1 FROM target_states AS t
   WHERE NOT EXISTS (
     SELECT 1 FROM lab05_seller_states AS s2
     WHERE s2.seller_id = s.seller_id AND s2.customer_state = t.state
   )
 )
)
SELECT COUNT(*) AS sellers_in_all_three_states FROM qualifying_sellers;

WITH qualifying_sellers AS (
 SELECT DISTINCT s.seller_id
 FROM lab05_seller_states AS s
 WHERE NOT EXISTS (
   SELECT 1 FROM target_states AS t
   WHERE NOT EXISTS (
     SELECT 1 FROM lab05_seller_states AS s2
     WHERE s2.seller_id = s.seller_id AND s2.customer_state = t.state
   )
 )
)
SELECT seller_id FROM qualifying_sellers ORDER BY seller_id LIMIT 10;

-- Контрольные вопросы:
-- 1. «Для всех x выполняется P(x)» = NOT EXISTS x, для которого NOT P(x).
-- 2. COUNT(DISTINCT state) сравнивают с числом обязательных штатов,
--    чтобы подтвердить наличие каждого штата и не учитывать повторные покупки.
-- 3. Если S пусто, не существует нарушающего элемента: условие истинно
--    для каждого кандидата. Простая HAVING-группировка по пустому S без
--    специальной обработки кандидатов не вернёт категории.

