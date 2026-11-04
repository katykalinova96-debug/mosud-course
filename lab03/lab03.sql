-- Практическая работа № 3. Выборка, проекция и переименование
-- Студент: Кураева Екатерина Алексеевна
-- Группа: ИНБО-22-23
-- Вариант: 6

-- 1. Исходное отношение и атрибуты

-- R = olist.order_reviews
-- Исходное отношение: таблица отзывов покупателей.
--
-- Используемые атрибуты:
-- order_id               - идентификатор заказа;
-- review_score           - оценка покупателя;
-- review_comment_message - текст отзыва.
--
-- Условие выборки:
-- review_score <= 2 AND review_comment_message IS NOT NULL
--
-- Итоговая проекция:
-- order_id, review_score, review_comment_message.
--
-- Переименование:
-- review_score -> score
-- review_comment_message -> comment_message

-- 2. Выражение реляционной алгебры

-- σ (сигма) - выборка строк по условию.
-- π (пи)    - проекция на нужные столбцы.
-- ρ (ро)    - переименование атрибутов.
--
-- R = olist.order_reviews
--
-- Полное выражение:
--
-- ρ_{score <- review_score,
--    comment_message <- review_comment_message}
-- (
--   π_{order_id, review_score, review_comment_message}
--   (
--     σ_{review_score <= 2 AND review_comment_message IS NOT NULL}(R)
--   )
-- )
--
-- Сначала отбираем строки с помощью σ,
-- затем оставляем нужные столбцы с помощью π,
-- после чего переименовываем атрибуты с помощью ρ.

-- 1–3. Исходный запрос: выборка, проекция и переименование.
-- LIMIT используется только для удобного просмотра примера, не для подсчёта.
SELECT order_id,
       review_score AS score,
       review_comment_message AS comment_message
FROM olist.order_reviews
WHERE review_score <= 2
  AND review_comment_message IS NOT NULL
ORDER BY order_id, score, comment_message
LIMIT 10;

-- 4. Две последовательные выборки вместо составного предиката.
WITH low_score AS (
    SELECT *
    FROM olist.order_reviews
    WHERE review_score <= 2
),
with_comment AS (
    SELECT *
    FROM low_score
    WHERE review_comment_message IS NOT NULL
)
SELECT count(*) AS sequential_filters_rows
FROM with_comment;

-- 5. Второй SQL-вариант: лишние столбцы исключены на ранней стадии.
-- Оставляем только атрибуты, необходимые для проверки и результата.
WITH narrow_reviews AS (
    SELECT order_id, review_score, review_comment_message
    FROM olist.order_reviews
),
low_score AS (
    SELECT * FROM narrow_reviews WHERE review_score <= 2
),
with_comment AS (
    SELECT * FROM low_score WHERE review_comment_message IS NOT NULL
)
SELECT count(*) AS early_projection_rows
FROM with_comment;

-- Сравнение количества строк исходного, последовательного и узкого вариантов.
WITH original AS (
    SELECT order_id, review_score AS score,
           review_comment_message AS comment_message
    FROM olist.order_reviews
    WHERE review_score <= 2 AND review_comment_message IS NOT NULL
),
sequential AS (
    SELECT order_id, review_score AS score,
           review_comment_message AS comment_message
    FROM (SELECT * FROM olist.order_reviews WHERE review_score <= 2) r
    WHERE review_comment_message IS NOT NULL
),
early_projection AS (
    SELECT order_id, review_score AS score,
           review_comment_message AS comment_message
    FROM (SELECT order_id, review_score, review_comment_message
          FROM olist.order_reviews) r
    WHERE review_score <= 2 AND review_comment_message IS NOT NULL
)
SELECT (SELECT count(*) FROM original) AS original_rows,
       (SELECT count(*) FROM sequential) AS sequential_rows,
       (SELECT count(*) FROM early_projection) AS early_projection_rows;

-- 4–5. Проверка эквивалентности с сохранением дубликатов.
-- EXCEPT ALL обнаружит разницу даже в кратности одинаковых строк.
WITH original AS (
    SELECT order_id, review_score AS score,
           review_comment_message AS comment_message
    FROM olist.order_reviews
    WHERE review_score <= 2 AND review_comment_message IS NOT NULL
),
sequential AS (
    SELECT order_id, review_score AS score,
           review_comment_message AS comment_message
    FROM (SELECT * FROM olist.order_reviews WHERE review_score <= 2) r
    WHERE review_comment_message IS NOT NULL
),
early_projection AS (
    SELECT order_id, review_score AS score,
           review_comment_message AS comment_message
    FROM (SELECT order_id, review_score, review_comment_message
          FROM olist.order_reviews) r
    WHERE review_score <= 2 AND review_comment_message IS NOT NULL
),
differences AS (
    (SELECT * FROM original EXCEPT ALL SELECT * FROM sequential)
    UNION ALL
    (SELECT * FROM sequential EXCEPT ALL SELECT * FROM original)
    UNION ALL
    (SELECT * FROM original EXCEPT ALL SELECT * FROM early_projection)
    UNION ALL
    (SELECT * FROM early_projection EXCEPT ALL SELECT * FROM original)
)
SELECT count(*) AS different_rows -- Ожидается 0
FROM differences;

-- 6. Могут ли в проекции возникнуть дубликаты?
-- Сравним полную проекцию из варианта с SELECT DISTINCT.
WITH selected AS (
    SELECT order_id, review_score AS score,
           review_comment_message AS comment_message
    FROM olist.order_reviews
    WHERE review_score <= 2 AND review_comment_message IS NOT NULL
)
SELECT count(*) AS select_rows,
       (SELECT count(*) FROM (SELECT DISTINCT * FROM selected) d) AS distinct_rows,
       count(*) - (SELECT count(*) FROM (SELECT DISTINCT * FROM selected) d) AS duplicate_rows
FROM selected;

-- Дополнительный пример проекции на один столбец: повторения оценок.
WITH selected AS (
    SELECT review_score AS score
    FROM olist.order_reviews
    WHERE review_score <= 2 AND review_comment_message IS NOT NULL
)
SELECT count(*) AS scores_with_repetitions,
       count(DISTINCT score) AS distinct_scores
FROM selected;
