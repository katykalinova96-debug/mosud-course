-- Практическая работа № 7. NULL, трёхзначная логика и качество данных
-- Студент: Кураева Екатерина Алексеевна
-- Группа: ИНБО-22-23
-- База: olist; схема исходных данных: olist
-- Исходные таблицы не изменяются. Создаётся только временная таблица.
-- Запускать весь файл в одном сеансе PostgreSQL.

-- 1. Число NULL во всех потенциально необязательных столбцах.
-- COUNT(*) FILTER (WHERE col IS NULL) считает строки с пропуском.
SELECT 'orders' AS table_name, COUNT(*) AS total_rows,
       COUNT(*) FILTER (WHERE order_status IS NULL) AS null_order_status,
       COUNT(*) FILTER (WHERE order_purchase_timestamp IS NULL) AS null_purchase_timestamp,
       COUNT(*) FILTER (WHERE order_approved_at IS NULL) AS null_approved_at,
       COUNT(*) FILTER (WHERE order_delivered_carrier_date IS NULL) AS null_carrier_date,
       COUNT(*) FILTER (WHERE order_delivered_customer_date IS NULL) AS null_customer_date,
       COUNT(*) FILTER (WHERE order_estimated_delivery_date IS NULL) AS null_estimated_delivery_date
FROM olist.orders;

SELECT 'products' AS table_name, COUNT(*) AS total_rows,
       COUNT(*) FILTER (WHERE product_category_name IS NULL) AS null_category,
       COUNT(*) FILTER (WHERE product_name_lenght IS NULL) AS null_name_length,
       COUNT(*) FILTER (WHERE product_description_lenght IS NULL) AS null_description_length,
       COUNT(*) FILTER (WHERE product_photos_qty IS NULL) AS null_photos_qty,
       COUNT(*) FILTER (WHERE product_weight_g IS NULL) AS null_weight_g,
       COUNT(*) FILTER (WHERE product_length_cm IS NULL) AS null_length_cm,
       COUNT(*) FILTER (WHERE product_height_cm IS NULL) AS null_height_cm,
       COUNT(*) FILTER (WHERE product_width_cm IS NULL) AS null_width_cm
FROM olist.products;

SELECT 'order_reviews' AS table_name, COUNT(*) AS total_rows,
       COUNT(*) FILTER (WHERE review_score IS NULL) AS null_review_score,
       COUNT(*) FILTER (WHERE review_comment_title IS NULL) AS null_comment_title,
       COUNT(*) FILTER (WHERE review_comment_message IS NULL) AS null_comment_message,
       COUNT(*) FILTER (WHERE review_creation_date IS NULL) AS null_creation_date,
       COUNT(*) FILTER (WHERE review_answer_timestamp IS NULL) AS null_answer_timestamp
FROM olist.order_reviews;

-- 2. COUNT(*) считает все заказы, COUNT(column) — только ненулевые даты.
-- Их разница равна числу заказов без фактической даты доставки.
SELECT COUNT(*) AS total_orders,
       COUNT(order_delivered_customer_date) AS orders_with_delivery_date,
       COUNT(*) - COUNT(order_delivered_customer_date) AS orders_without_delivery_date
FROM olist.orders;

-- 3. Некорректное сравнение с NULL и правильная альтернатива.
-- Оба сравнения (= NULL и <> NULL) дают UNKNOWN; WHERE их отбрасывает.
SELECT 'equal_null_wrong' AS test, COUNT(*) AS row_count
FROM olist.orders WHERE order_delivered_customer_date = NULL
UNION ALL
SELECT 'not_equal_null_wrong', COUNT(*)
FROM olist.orders WHERE order_delivered_customer_date <> NULL
UNION ALL
SELECT 'is_null_correct', COUNT(*)
FROM olist.orders WHERE order_delivered_customer_date IS NULL
UNION ALL
SELECT 'is_not_null_correct', COUNT(*)
FROM olist.orders WHERE order_delivered_customer_date IS NOT NULL;

-- 4. IS DISTINCT FROM: всегда TRUE/FALSE, даже при NULL.
-- NULL и NULL считаются неразличимыми; NULL и число — различными.
SELECT a, b,
       a <> b AS ordinary_not_equal,
       a IS DISTINCT FROM b AS is_distinct,
       a IS NOT DISTINCT FROM b AS is_not_distinct
FROM (VALUES (10, 10), (10, 20), (10, NULL), (NULL, NULL)) AS v(a, b);

-- 5. NOT IN и NOT EXISTS при наличии NULL в подзапросе.
-- Временная таблица содержит один реально существующий order_id и NULL.
DROP TABLE IF EXISTS pg_temp.temp_ids;
CREATE TEMP TABLE temp_ids (id text) ON COMMIT PRESERVE ROWS;
INSERT INTO temp_ids (id)
SELECT order_id FROM olist.orders ORDER BY order_id LIMIT 1;
INSERT INTO temp_ids (id) VALUES (NULL);

SELECT id FROM temp_ids ORDER BY id NULLS LAST;

-- NOT IN при наличии NULL не выбирает ожидаемые отсутствующие ID:
-- для остальных ID сравнение становится UNKNOWN.
SELECT 'not_in' AS method, COUNT(*) AS row_count
FROM olist.orders AS o
WHERE o.order_id NOT IN (SELECT t.id FROM temp_ids AS t)
UNION ALL
-- NOT EXISTS не зависит от того, есть ли NULL среди значений temp_ids.
SELECT 'not_exists', COUNT(*)
FROM olist.orders AS o
WHERE NOT EXISTS (
    SELECT 1 FROM temp_ids AS t WHERE t.id = o.order_id
);

-- Контроль: исключить NULL из NOT IN — результаты совпадут с NOT EXISTS.
SELECT 'not_in_without_null' AS method, COUNT(*) AS row_count
FROM olist.orders AS o
WHERE o.order_id NOT IN (SELECT t.id FROM temp_ids AS t WHERE t.id IS NOT NULL);

-- 6. LEFT JOIN reviews: предикат >= 4 в ON и в WHERE.
-- В ON сохраняются все заказы; при отсутствии подходящего отзыва r.* = NULL.
SELECT 'filter_in_on' AS method,
       COUNT(*) AS joined_rows,
       COUNT(DISTINCT o.order_id) AS distinct_orders,
       COUNT(r.review_id) AS matched_reviews
FROM olist.orders AS o
LEFT JOIN olist.order_reviews AS r
  ON r.order_id = o.order_id AND r.review_score >= 4
UNION ALL
-- В WHERE строки без подходящего отзыва исключаются.
SELECT 'filter_in_where',
       COUNT(*), COUNT(DISTINCT o.order_id), COUNT(r.review_id)
FROM olist.orders AS o
LEFT JOIN olist.order_reviews AS r ON r.order_id = o.order_id
WHERE r.review_score >= 4;

-- 7. COALESCE подставляет текст вместо NULL; пустую строку не заменяет.
SELECT review_id, review_score,
       COALESCE(review_comment_message, 'Нет комментария') AS comment_text
FROM olist.order_reviews
ORDER BY review_id LIMIT 10;

-- NULLIF(делитель, 0) превращает нулевой делитель в NULL.
-- Поэтому вместо ошибки деления на ноль результатом будет NULL.
SELECT 10.0 / NULLIF(0, 0) AS safe_division_by_zero,
       10.0 / NULLIF(2, 0) AS ordinary_division;

-- Расчёт процента непустых комментариев с безопасным делением.
SELECT COUNT(*) AS total_reviews,
       COUNT(review_comment_message) AS reviews_with_text,
       ROUND(100.0 * COUNT(review_comment_message) / NULLIF(COUNT(*), 0), 2)
         AS reviews_with_text_pct
FROM olist.order_reviews;

-- 8. Мини-профиль качества данных: абсолютные и относительные пропуски.
-- Процент = 100 * число пропусков / общее число строк.
SELECT 'orders_without_delivery_date' AS metric,
       COUNT(*) AS total_rows,
       COUNT(*) FILTER (WHERE order_delivered_customer_date IS NULL) AS missing_rows,
       ROUND(100.0 * COUNT(*) FILTER (WHERE order_delivered_customer_date IS NULL)
             / NULLIF(COUNT(*), 0), 2) AS missing_pct
FROM olist.orders
UNION ALL
SELECT 'products_without_category', COUNT(*),
       COUNT(*) FILTER (WHERE product_category_name IS NULL),
       ROUND(100.0 * COUNT(*) FILTER (WHERE product_category_name IS NULL)
             / NULLIF(COUNT(*), 0), 2)
FROM olist.products
UNION ALL
SELECT 'reviews_without_text', COUNT(*),
       COUNT(*) FILTER (WHERE review_comment_message IS NULL),
       ROUND(100.0 * COUNT(*) FILTER (WHERE review_comment_message IS NULL)
             / NULLIF(COUNT(*), 0), 2)
FROM olist.order_reviews
ORDER BY metric;

-- 9. Предметная интерпретация NULL.
-- Отсутствие даты доставки для отменённого заказа естественно:
-- фактическая доставка могла не состояться.
-- Для delivered отсутствие даты доставки потребовало бы проверки.
SELECT order_status, COUNT(*) AS total_orders,
       COUNT(*) FILTER (WHERE order_delivered_customer_date IS NULL) AS without_delivery_date
FROM olist.orders
GROUP BY order_status
ORDER BY order_status;

-- NULL в product_category_name — потенциальная проблема полноты каталога:
-- товар нельзя корректно распределить по категориям для аналитики.
SELECT COUNT(*) AS total_products,
       COUNT(*) FILTER (WHERE product_category_name IS NULL) AS without_category
FROM olist.products;
