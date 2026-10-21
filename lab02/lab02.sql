-- Практическая работа № 2. Множества и мультимножества в SQL
-- ФИО: Кураева Екатерина Алексеевна
-- Группа: ИНБО-22-23
-- Вариант: 6. X = ES, Y = RJ.

-- 1. Мультимножества покупок A и B: количество всех строк и уникальных товаров.
SELECT c.customer_state AS state,
       COUNT(*) AS all_rows,
       COUNT(DISTINCT oi.product_id) AS distinct_products
FROM olist.customers AS c
JOIN olist.orders AS o ON o.customer_id = c.customer_id
JOIN olist.order_items AS oi ON oi.order_id = o.order_id
WHERE o.order_status = 'delivered'
  AND c.customer_state IN ('ES', 'RJ')
GROUP BY c.customer_state
ORDER BY c.customer_state;

-- 1 Собственно запрос A: уникальные product_id для ES.
SELECT DISTINCT oi.product_id
FROM olist.customers AS c
JOIN olist.orders AS o ON o.customer_id = c.customer_id
JOIN olist.order_items AS oi ON oi.order_id = o.order_id
WHERE o.order_status = 'delivered' AND c.customer_state = 'ES';

-- 1 Запрос B: уникальные product_id для RJ.
SELECT DISTINCT oi.product_id
FROM olist.customers AS c
JOIN olist.orders AS o ON o.customer_id = c.customer_id
JOIN olist.order_items AS oi ON oi.order_id = o.order_id
WHERE o.order_status = 'delivered' AND c.customer_state = 'RJ';

-- Для пунктов 2–8 используем временные представления в текущем сеансе.
-- Они содержат по одному вхождению каждого product_id (настоящие множества).
CREATE OR REPLACE TEMP VIEW a AS
SELECT DISTINCT oi.product_id
FROM olist.customers AS c
JOIN olist.orders AS o ON o.customer_id = c.customer_id
JOIN olist.order_items AS oi ON oi.order_id = o.order_id
WHERE o.order_status = 'delivered' AND c.customer_state = 'ES';

CREATE OR REPLACE TEMP VIEW b AS
SELECT DISTINCT oi.product_id
FROM olist.customers AS c
JOIN olist.orders AS o ON o.customer_id = c.customer_id
JOIN olist.order_items AS oi ON oi.order_id = o.order_id
WHERE o.order_status = 'delivered' AND c.customer_state = 'RJ';

-- 2. UNION удаляет дубликаты, UNION ALL сохраняет совпадающие product_id.
SELECT COUNT(*) AS union_rows
FROM (SELECT product_id FROM a UNION SELECT product_id FROM b) AS u;
SELECT COUNT(*) AS union_all_rows
FROM (SELECT product_id FROM a UNION ALL SELECT product_id FROM b) AS ua;

-- 3. Пересечение: товары, встречающиеся в обоих штатах.
SELECT COUNT(*) AS intersection_rows
FROM (SELECT product_id FROM a INTERSECT SELECT product_id FROM b) AS i;

-- 4. Разности множеств: только в ES и только в RJ.
SELECT COUNT(*) AS a_minus_b_rows
FROM (SELECT product_id FROM a EXCEPT SELECT product_id FROM b) AS d;
SELECT COUNT(*) AS b_minus_a_rows
FROM (SELECT product_id FROM b EXCEPT SELECT product_id FROM a) AS d;

-- 5. Коммутативность UNION и INTERSECT: результат не зависит от порядка.
SELECT
  (SELECT COUNT(*) FROM (SELECT product_id FROM a UNION SELECT product_id FROM b) AS x) =
  (SELECT COUNT(*) FROM (SELECT product_id FROM b UNION SELECT product_id FROM a) AS x)
  AS union_commutative,
  (SELECT COUNT(*) FROM (SELECT product_id FROM a INTERSECT SELECT product_id FROM b) AS x) =
  (SELECT COUNT(*) FROM (SELECT product_id FROM b INTERSECT SELECT product_id FROM a) AS x)
  AS intersect_commutative;

-- 6. Разность некоммутативна: A - B и B - A содержат разные товары.
-- Сравниваем сами наборы, а не только количество элементов.
SELECT EXISTS (
  (SELECT product_id FROM (SELECT product_id FROM a EXCEPT SELECT product_id FROM b) AS x
   EXCEPT
   SELECT product_id FROM (SELECT product_id FROM b EXCEPT SELECT product_id FROM a) AS y)
  UNION ALL
  (SELECT product_id FROM (SELECT product_id FROM b EXCEPT SELECT product_id FROM a) AS y
   EXCEPT
   SELECT product_id FROM (SELECT product_id FROM a EXCEPT SELECT product_id FROM b) AS x)
) AS differences_are_different;

-- 7. Пересечение через EXISTS без INTERSECT.
SELECT COUNT(*) AS intersection_exists_rows
FROM a
WHERE EXISTS (SELECT 1 FROM b WHERE b.product_id = a.product_id);

-- 8. Уберем DISTINCT: повторяющиеся покупки создают дубликаты.
SELECT COUNT(*) AS rows_without_distinct,
       COUNT(DISTINCT oi.product_id) AS unique_products,
       COUNT(*) - COUNT(DISTINCT oi.product_id) AS extra_duplicate_rows
FROM olist.customers AS c
JOIN olist.orders AS o ON o.customer_id = c.customer_id
JOIN olist.order_items AS oi ON oi.order_id = o.order_id
WHERE o.order_status = 'delivered' AND c.customer_state = 'ES';

-- 9. Комментарий: DISTINCT, UNION, INTERSECT, EXCEPT возвращают множество
-- уникальных product_id. UNION ALL и обычный SELECT без DISTINCT могут
-- возвращать мультимножество: один и тот же product_id повторяется.
-- Порядок строк не гарантирован, если не указан ORDER BY.

-- Итоговая таблица для README.md: мощности всех множеств.
SELECT
  (SELECT COUNT(*) FROM a) AS a,
  (SELECT COUNT(*) FROM b) AS b,
  (SELECT COUNT(*) FROM (SELECT product_id FROM a UNION SELECT product_id FROM b) AS t) AS a_union_b,
  (SELECT COUNT(*) FROM (SELECT product_id FROM a UNION ALL SELECT product_id FROM b) AS t) AS a_union_all_b,
  (SELECT COUNT(*) FROM (SELECT product_id FROM a INTERSECT SELECT product_id FROM b) AS t) AS a_intersect_b,
  (SELECT COUNT(*) FROM (SELECT product_id FROM a EXCEPT SELECT product_id FROM b) AS t) AS a_minus_b,
  (SELECT COUNT(*) FROM (SELECT product_id FROM b EXCEPT SELECT product_id FROM a) AS t) AS b_minus_a;
