-- ============================================================
-- Практическая работа №1
-- ФИО: Кураева Екатерина Алексеевна
-- Группа: ИНБО-22-23
-- Проверки целостности данных
-- ============================================================

-- Сбор статистики для оптимизатора
ANALYZE olist.customers;
ANALYZE olist.geolocation;
ANALYZE olist.orders;
ANALYZE olist.order_items;
ANALYZE olist.order_payments;
ANALYZE olist.order_reviews;
ANALYZE olist.products;
ANALYZE olist.sellers;
ANALYZE olist.product_category_name_translation;

-- Количество строк во всех таблицах
SELECT 'customers' AS table_name, count(*) AS row_count FROM olist.customers UNION ALL
SELECT 'geolocation', count(*) FROM olist.geolocation UNION ALL
SELECT 'orders', count(*) FROM olist.orders UNION ALL
SELECT 'order_items', count(*) FROM olist.order_items UNION ALL
SELECT 'order_payments', count(*) FROM olist.order_payments UNION ALL
SELECT 'order_reviews', count(*) FROM olist.order_reviews UNION ALL
SELECT 'products', count(*) FROM olist.products UNION ALL
SELECT 'sellers', count(*) FROM olist.sellers UNION ALL
SELECT 'product_category_name_translation', count(*) FROM olist.product_category_name_translation
ORDER BY table_name;

-- Проверка на NULL в первичных ключах (должно быть 0)
SELECT 'orders_pk_nulls' AS check_name, count(*) AS null_count FROM olist.orders WHERE order_id IS NULL UNION ALL
SELECT 'customers_pk_nulls', count(*) FROM olist.customers WHERE customer_id IS NULL UNION ALL
SELECT 'products_pk_nulls', count(*) FROM olist.products WHERE product_id IS NULL UNION ALL
SELECT 'sellers_pk_nulls', count(*) FROM olist.sellers WHERE seller_id IS NULL;

--Проверка ссылочной целостности (осиротевшие записи — должно быть 0)
SELECT 'orphan_order_items' AS check_name, count(*) AS orphan_count
FROM olist.order_items oi 
LEFT JOIN olist.orders o ON o.order_id = oi.order_id 
WHERE o.order_id IS NULL
UNION ALL
SELECT 'orphan_orders_customer', count(*)
FROM olist.orders o 
LEFT JOIN olist.customers c ON c.customer_id = o.customer_id 
WHERE c.customer_id IS NULL
UNION ALL
SELECT 'orphan_order_payments', count(*)
FROM olist.order_payments op 
LEFT JOIN olist.orders o ON o.order_id = op.order_id 
WHERE o.order_id IS NULL
UNION ALL
SELECT 'orphan_order_reviews', count(*)
FROM olist.order_reviews orv 
LEFT JOIN olist.orders o ON o.order_id = orv.order_id 
WHERE o.order_id IS NULL;