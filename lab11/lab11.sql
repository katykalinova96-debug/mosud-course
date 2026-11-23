-- Практическая работа № 11. Представления, CTE и рекурсивные запросы
-- Кураева Екатерина Алексеевна, ИНБО-22-23. Вариант 6: штат SC.
-- PostgreSQL 17, база olist. Создаваемые объекты находятся только в lab.
-- Повторный запуск пересоздаёт объекты именно этой практической.

CREATE SCHEMA IF NOT EXISTS lab;

-- 1. Обычное представление: ровно одна строка на заказ.
-- LEFT JOIN сохраняет заказы, даже если позиций в order_items нет.
CREATE OR REPLACE VIEW lab.v_order_summary AS
SELECT o.order_id,
       o.order_purchase_timestamp AS purchase_at,
       c.customer_state,
       COUNT(oi.order_item_id)::bigint AS item_count,
       COALESCE(SUM(oi.price + oi.freight_value), 0)::numeric(18,2) AS total_value
FROM olist.orders AS o
JOIN olist.customers AS c ON c.customer_id = o.customer_id
LEFT JOIN olist.order_items AS oi ON oi.order_id = o.order_id
GROUP BY o.order_id, o.order_purchase_timestamp, c.customer_state;

-- Проверка соответствия количества строк числу заказов.
SELECT (SELECT COUNT(*) FROM olist.orders) AS orders_count,
       (SELECT COUNT(*) FROM lab.v_order_summary) AS view_count,
       (SELECT COUNT(*) FROM lab.v_order_summary WHERE item_count = 0) AS no_items_count;

-- 2. Материализованное представление: месяц и штат, количество заказов и сумма.
DROP MATERIALIZED VIEW IF EXISTS lab.mv_monthly_state_sales;
CREATE MATERIALIZED VIEW lab.mv_monthly_state_sales AS
SELECT date_trunc('month', purchase_at)::date AS month_start,
       customer_state,
       COUNT(*)::bigint AS order_count,
       SUM(total_value)::numeric(18,2) AS sales_value
FROM lab.v_order_summary
WHERE purchase_at IS NOT NULL
GROUP BY date_trunc('month', purchase_at)::date, customer_state
WITH DATA;

-- Обновление физически сохранённых результатов.
REFRESH MATERIALIZED VIEW lab.mv_monthly_state_sales;
SELECT COUNT(*) AS monthly_state_groups
FROM lab.mv_monthly_state_sales;

-- 3. Аналитика через три именованных CTE: месяцы, агрегирование, ранжирование.
WITH order_data AS (
    SELECT date_trunc('month', purchase_at)::date AS month_start,
           customer_state, total_value
    FROM lab.v_order_summary
    WHERE purchase_at IS NOT NULL
),
state_monthly AS (
    SELECT month_start, customer_state,
           COUNT(*) AS order_count,
           SUM(total_value)::numeric(18,2) AS sales_value
    FROM order_data
    GROUP BY month_start, customer_state
),
ranked_states AS (
    SELECT month_start, customer_state, order_count, sales_value,
           ROW_NUMBER() OVER (
               PARTITION BY month_start
               ORDER BY sales_value DESC, customer_state
           ) AS state_rank
    FROM state_monthly
)
SELECT month_start, customer_state, order_count, sales_value, state_rank
FROM ranked_states
WHERE state_rank <= 3
ORDER BY month_start DESC, state_rank
LIMIT 15;

-- 4. Иерархия BR -> штат -> город на реальных olist.customers.
-- В каждом штате берутся не более 20 городов с наибольшим числом клиентов.
DROP TABLE IF EXISTS lab.geo_tree;
CREATE TABLE lab.geo_tree (
    node_id text CONSTRAINT pk_geo_tree PRIMARY KEY,
    parent_id text,
    node_type text NOT NULL,
    node_name text NOT NULL,
    CONSTRAINT fk_geo_tree_parent FOREIGN KEY (parent_id)
        REFERENCES lab.geo_tree (node_id),
    CONSTRAINT ck_geo_tree_type CHECK (
        node_type IN ('country', 'state', 'city')
    )
);

INSERT INTO lab.geo_tree (node_id, parent_id, node_type, node_name)
VALUES ('BR', NULL, 'country', 'Brazil');

INSERT INTO lab.geo_tree (node_id, parent_id, node_type, node_name)
SELECT 'ST:' || customer_state, 'BR', 'state', customer_state
FROM olist.customers
WHERE customer_state IS NOT NULL
GROUP BY customer_state;

WITH city_counts AS (
    SELECT customer_state, customer_city, COUNT(*) AS customer_count
    FROM olist.customers
    WHERE customer_state IS NOT NULL
      AND customer_city IS NOT NULL
    GROUP BY customer_state, customer_city
),
city_ranked AS (
    SELECT customer_state, customer_city, customer_count,
           ROW_NUMBER() OVER (
               PARTITION BY customer_state
               ORDER BY customer_count DESC, customer_city
           ) AS rn
    FROM city_counts
)
INSERT INTO lab.geo_tree (node_id, parent_id, node_type, node_name)
SELECT 'CT:' || customer_state || ':' || customer_city,
       'ST:' || customer_state,
       'city', customer_city
FROM city_ranked
WHERE rn <= 20;

SELECT node_type, COUNT(*) AS nodes
FROM lab.geo_tree
GROUP BY node_type
ORDER BY node_type;

SELECT parent_id AS state_node, COUNT(*) AS city_nodes
FROM lab.geo_tree
WHERE node_type = 'city'
GROUP BY parent_id
ORDER BY parent_id;

-- 5. Поддерево своего варианта: SC, глубина, ID, путь, имя.
WITH RECURSIVE subtree AS (
    SELECT node_id, parent_id, node_name, 0 AS depth,
           node_id::text AS path,
           ARRAY[node_id]::text[] AS visited
    FROM lab.geo_tree
    WHERE node_id = 'ST:SC'
    UNION ALL
    SELECT g.node_id, g.parent_id, g.node_name, s.depth + 1,
           s.path || ' -> ' || g.node_id,
           s.visited || g.node_id
    FROM lab.geo_tree AS g
    JOIN subtree AS s ON g.parent_id = s.node_id
    WHERE NOT (g.node_id = ANY(s.visited))
)
SELECT depth, node_id, path, node_name
FROM subtree
ORDER BY depth, node_id;

-- 6. Обратная рекурсия: предки первого города SC (по node_id) до BR.
WITH RECURSIVE ancestors AS (
    SELECT node_id, parent_id, node_name, 0 AS depth,
           node_id::text AS path,
           ARRAY[node_id]::text[] AS visited
    FROM lab.geo_tree
    WHERE node_id = (
        SELECT MIN(node_id)
        FROM lab.geo_tree
        WHERE node_type = 'city' AND parent_id = 'ST:SC'
    )
    UNION ALL
    SELECT g.node_id, g.parent_id, g.node_name, a.depth + 1,
           a.path || ' -> ' || g.node_id,
           a.visited || g.node_id
    FROM lab.geo_tree AS g
    JOIN ancestors AS a ON g.node_id = a.parent_id
    WHERE NOT (g.node_id = ANY(a.visited))
)
SELECT depth, node_id, path, node_name
FROM ancestors
ORDER BY depth;

-- 7. Число всех потомков каждого штата (не только непосредственных детей).
WITH RECURSIVE descendants AS (
    SELECT node_id AS state_id, node_id AS descendant_id,
           ARRAY[node_id]::text[] AS visited
    FROM lab.geo_tree
    WHERE node_type = 'state'
    UNION ALL
    SELECT d.state_id, g.node_id, d.visited || g.node_id
    FROM descendants AS d
    JOIN lab.geo_tree AS g ON g.parent_id = d.descendant_id
    WHERE NOT (g.node_id = ANY(d.visited))
)
SELECT state_id, COUNT(*) - 1 AS descendant_count
FROM descendants
GROUP BY state_id
ORDER BY state_id;

-- 8*. Необязательное задание: искусственный цикл в независимой копии.
-- Изменяем только временную таблицу; исходная lab.geo_tree остаётся корректной.
DROP TABLE IF EXISTS pg_temp.geo_tree_cycle;
CREATE TEMP TABLE geo_tree_cycle AS TABLE lab.geo_tree;
UPDATE geo_tree_cycle
SET parent_id = (
    SELECT MIN(node_id)
    FROM geo_tree_cycle
    WHERE parent_id = 'ST:SC' AND node_type = 'city'
)
WHERE node_id = 'ST:SC';
-- Получился цикл ST:SC -> город SC -> ST:SC при обходе вниз.
-- visited не допускает повторного разворачивания узла.
WITH RECURSIVE protected_tree AS (
    SELECT node_id, parent_id, 0 AS depth,
           ARRAY[node_id]::text[] AS visited
    FROM geo_tree_cycle
    WHERE node_id = 'ST:SC'
    UNION ALL
    SELECT g.node_id, g.parent_id, p.depth + 1,
           p.visited || g.node_id
    FROM geo_tree_cycle AS g
    JOIN protected_tree AS p ON g.parent_id = p.node_id
    WHERE NOT (g.node_id = ANY(p.visited))
)
SELECT COUNT(*) AS rows_without_infinite_cycle,
       MAX(depth) AS max_depth
FROM protected_tree;

-- Контроль: ссылка каждого узла на существующего родителя.
SELECT COUNT(*) AS invalid_parent_links
FROM lab.geo_tree AS g
LEFT JOIN lab.geo_tree AS p ON p.node_id = g.parent_id
WHERE g.parent_id IS NOT NULL AND p.node_id IS NULL;
