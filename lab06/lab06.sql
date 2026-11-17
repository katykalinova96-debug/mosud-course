-- Практическая работа № 6. Подзапросы и логика предикатов
-- Студент: Кураева Екатерина Алексеевна
-- Группа: ИНБО-22-23
-- Вариант: 6
-- Задача: найти заказы, у которых сумма платежей больше суммы
--         price + freight_value по товарным позициям заказа.
-- База: olist, схема исходных данных: olist.
-- Все запросы только читают данные; исходные таблицы не изменяются.

-- 1–2. Основное решение: коррелированные скалярные подзапросы + EXISTS.
-- Скалярные подзапросы для каждого order_id возвращают по одному числу:
-- общую сумму платежей и общую стоимость позиций с доставкой.
-- EXISTS проверяет, что у заказа есть платежи и товарные позиции.
-- Снаружи сравниваем две вычисленные суммы.
CREATE OR REPLACE TEMP VIEW lab06_main AS
WITH sums_by_order AS (
    SELECT
        o.order_id,
        (SELECT SUM(p.payment_value)
         FROM olist.order_payments AS p
         WHERE p.order_id = o.order_id) AS payment_total,
        (SELECT SUM(oi.price + oi.freight_value)
         FROM olist.order_items AS oi
         WHERE oi.order_id = o.order_id) AS items_total
    FROM olist.orders AS o
    WHERE EXISTS (
        SELECT 1
        FROM olist.order_payments AS p
        WHERE p.order_id = o.order_id
    )
      AND EXISTS (
        SELECT 1
        FROM olist.order_items AS oi
        WHERE oi.order_id = o.order_id
    )
)
SELECT order_id, payment_total, items_total
FROM sums_by_order
WHERE payment_total > items_total;

-- Сколько заказов удовлетворяют условию (основной способ)?
SELECT COUNT(*) AS main_rows FROM lab06_main;

-- Примеры подходящих заказов и разница сумм.
SELECT order_id, payment_total, items_total,
       payment_total - items_total AS excess_payment
FROM lab06_main
ORDER BY excess_payment DESC, order_id
LIMIT 10;

-- 3. Альтернативное решение: CTE с предварительной агрегацией + JOIN.
-- Сначала независимо суммируем платежи и позиции по order_id.
-- Затем соединяем две агрегированные таблицы и сравниваем суммы.
CREATE OR REPLACE TEMP VIEW lab06_alt AS
WITH payment_sums AS (
    SELECT order_id, SUM(payment_value) AS payment_total
    FROM olist.order_payments
    GROUP BY order_id
),
item_sums AS (
    SELECT order_id, SUM(price + freight_value) AS items_total
    FROM olist.order_items
    GROUP BY order_id
)
SELECT p.order_id, p.payment_total, i.items_total
FROM payment_sums AS p
JOIN item_sums AS i ON i.order_id = p.order_id
WHERE p.payment_total > i.items_total;

-- Сколько заказов удовлетворяют условию (альтернативный способ)?
SELECT COUNT(*) AS alternative_rows FROM lab06_alt;

-- 4. Проверка эквивалентности: разность в обе стороны.
-- Сравниваем идентификаторы заказов: если обе разности пусты,
-- основной и альтернативный запросы находят одни и те же заказы.
SELECT 'main_minus_alt' AS check_direction, COUNT(*) AS different_orders
FROM (
    SELECT order_id FROM lab06_main
    EXCEPT
    SELECT order_id FROM lab06_alt
) AS d
UNION ALL
SELECT 'alt_minus_main' AS check_direction, COUNT(*) AS different_orders
FROM (
    SELECT order_id FROM lab06_alt
    EXCEPT
    SELECT order_id FROM lab06_main
) AS d;

-- 5. Отдельная демонстрация ANY.
-- Выбираем заказы, сумма платежей которых больше стоимости
-- хотя бы одной отдельной позиции (price + freight_value).
-- это НЕ равнозначно основной задаче: в ней сравниваются
-- суммы по ВСЕМ позициям заказа, а тут достаточно одной позиции.
WITH payment_sums AS (
    SELECT order_id, SUM(payment_value) AS payment_total
    FROM olist.order_payments
    GROUP BY order_id
)
SELECT p.order_id, p.payment_total
FROM payment_sums AS p
WHERE p.payment_total > ANY (
    SELECT oi.price + oi.freight_value
    FROM olist.order_items AS oi
    WHERE oi.order_id = p.order_id
)
ORDER BY p.order_id
LIMIT 10;
