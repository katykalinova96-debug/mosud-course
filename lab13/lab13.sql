-- Практическая работа № 13. Индексы и физический доступ к данным
-- Кураева Екатерина Алексеевна, ИНБО-22-23. Вариант 6.
-- PostgreSQL 17, база olist, таблица olist.products.
-- Запускать через psql: используется команда \gset.
-- Исходные данные не изменяются. PK и сторонние индексы не удаляются.

\echo '=== 1. Существующие индексы (для контроля) ==='
SELECT indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'olist' AND tablename = 'products'
ORDER BY indexname;

-- Повторный запуск: удаляем только индексы с именами ЭТОЙ практической.
DROP INDEX IF EXISTS olist.idx_lab13_products_category_weight;
DROP INDEX IF EXISTS olist.idx_lab13_products_weight_partial;

-- Выбираем категорию с небольшим, но ненулевым количеством товаров
-- в диапазоне веса 100..500 г. Реальные данные определяют категорию.
SELECT product_category_name AS category
FROM olist.products
WHERE product_category_name IS NOT NULL
  AND product_weight_g BETWEEN 100 AND 500
GROUP BY product_category_name
HAVING COUNT(*) BETWEEN 5 AND 500
ORDER BY COUNT(*) DESC, product_category_name
LIMIT 1
\gset

\echo '=== 2. Выбранная категория: ' :category ' ==='
SELECT product_category_name, COUNT(*) AS matched_rows
FROM olist.products
WHERE product_category_name = :'category'
  AND product_weight_g BETWEEN 100 AND 500
GROUP BY product_category_name;

-- Селективный запрос: равенство по категории и диапазон веса.
\echo '=== 3. ДО индекса: EXPLAIN (ANALYZE, BUFFERS) ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT product_id, product_category_name, product_weight_g
FROM olist.products
WHERE product_category_name = :'category'
  AND product_weight_g BETWEEN 100 AND 500;

-- Равенство по первому столбцу, диапазон по второму.
\echo '=== 4. Создание составного B-tree ==='
CREATE INDEX idx_lab13_products_category_weight
ON olist.products (product_category_name, product_weight_g);
ANALYZE olist.products;

\echo '=== 5. ПОСЛЕ индекса: EXPLAIN (ANALYZE, BUFFERS) ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT product_id, product_category_name, product_weight_g
FROM olist.products
WHERE product_category_name = :'category'
  AND product_weight_g BETWEEN 100 AND 500;

-- Низкая селективность: большинство товаров имеют вес > 0.
-- Планировщик вправе предпочесть Seq Scan, несмотря на индекс.
\echo '=== 6. Низкоселективный запрос: план ==='
SELECT COUNT(*) FILTER (WHERE product_category_name IS NOT NULL AND product_weight_g > 0)
           AS low_selectivity_rows,
       COUNT(*) AS total_rows
FROM olist.products;
EXPLAIN (ANALYZE, BUFFERS)
SELECT product_id, product_category_name, product_weight_g
FROM olist.products
WHERE product_category_name IS NOT NULL
  AND product_weight_g > 0;

\echo '=== 7. Размер составного индекса ==='
SELECT pg_size_pretty(pg_relation_size('olist.idx_lab13_products_category_weight'::regclass)) AS index_size,
       pg_relation_size('olist.idx_lab13_products_category_weight'::regclass) AS index_bytes;

-- Второй индекс другого типа: частичный, хранит веса только одной
-- выбранной категории. Условие совпадает с фильтром запросов.
\echo '=== 8. Частичный индекс ==='
CREATE INDEX idx_lab13_products_weight_partial
ON olist.products (product_weight_g)
WHERE product_category_name = :'category';
ANALYZE olist.products;

SELECT pg_size_pretty(pg_relation_size('olist.idx_lab13_products_weight_partial'::regclass)) AS partial_index_size,
       pg_relation_size('olist.idx_lab13_products_weight_partial'::regclass) AS partial_index_bytes;

\echo '=== 9. План при наличии двух индексов ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT product_id, product_category_name, product_weight_g
FROM olist.products
WHERE product_category_name = :'category'
  AND product_weight_g BETWEEN 100 AND 500;

\echo '=== 10. Очистка: удаление только двух тестовых индексов ==='
DROP INDEX IF EXISTS olist.idx_lab13_products_weight_partial;
DROP INDEX IF EXISTS olist.idx_lab13_products_category_weight;

\echo '=== Проверка: тестовых индексов не осталось ==='
SELECT indexname
FROM pg_indexes
WHERE schemaname = 'olist' AND tablename = 'products'
  AND indexname LIKE 'idx_lab13_%';
