SET TIME ZONE 'UTC';

-- Общий размер данных
SELECT COUNT(*)                AS events,
       COUNT(DISTINCT user_id) AS users,
       MIN(event_time)         AS first_event,
       MAX(event_time)         AS last_event
FROM events;

-- Распределение типов событий
SELECT event_type,
       COUNT(*) AS events,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct
FROM events
GROUP BY event_type
ORDER BY events DESC;

-- Дубликаты
SELECT COUNT(*)     AS duplicate_groups,
       SUM(cnt - 1) AS extra_rows
FROM (
    SELECT user_id, event_time, product_id, event_type, COUNT(*) AS cnt
    FROM events
    GROUP BY user_id, event_time, product_id, event_type
    HAVING COUNT(*) > 1
) t;

-- Дубликаты по типам событий
SELECT event_type,
       COUNT(*)     AS duplicate_groups,
       SUM(cnt - 1) AS extra_rows
FROM (
    SELECT user_id, event_time, product_id, event_type, COUNT(*) AS cnt
    FROM events
    GROUP BY user_id, event_time, product_id, event_type
    HAVING COUNT(*) > 1
) t
GROUP BY event_type
ORDER BY extra_rows DESC;


-- Пропуски и некорректные значения
SELECT COUNT(*) AS total,
       COUNT(*) FILTER (WHERE price IS NULL)                                AS price_null,
       COUNT(*) FILTER (WHERE price <= 0)                                   AS price_nonpositive,
       COUNT(*) FILTER (WHERE brand IS NULL OR brand = '')                  AS brand_missing,
       COUNT(*) FILTER (WHERE category_code IS NULL OR category_code = '')  AS category_missing,
       COUNT(*) FILTER (WHERE user_id IS NULL)                              AS user_null
FROM events;

-- Где встречаются нулевые и отрицательные цены
SELECT event_type, COUNT(*) AS rows_with_bad_price
FROM events
WHERE price <= 0
GROUP BY event_type
ORDER BY rows_with_bad_price DESC;

-- Активность по дням 
SELECT (event_time AT TIME ZONE 'UTC')::date AS day,
       COUNT(*)                AS events,
       COUNT(DISTINCT user_id) AS users
FROM events
GROUP BY 1
ORDER BY 1;

-- Очищенное представление
CREATE OR REPLACE VIEW events_clean AS
SELECT event_time,
       (event_time AT TIME ZONE 'UTC')::date     AS event_date,
       event_type,
       product_id,
       category_code,
       COALESCE(NULLIF(brand, ''), 'unknown')    AS brand,
       price,
       (price > 0)                               AS price_valid,
       user_id
FROM events
WHERE user_id IS NOT NULL
  AND event_type IN ('view', 'cart', 'remove_from_cart', 'purchase');

-- Проверка
SELECT COUNT(*) AS rows_clean FROM events_clean;
