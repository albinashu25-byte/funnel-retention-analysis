SET TIME ZONE 'UTC';

-- Одна строка на пользователя
DROP TABLE IF EXISTS user_funnel;

CREATE TABLE user_funnel AS
SELECT user_id,
       MIN(event_time)                                        AS first_seen,
       MIN(event_time) FILTER (WHERE event_type = 'view')     AS t_view,
       MIN(event_time) FILTER (WHERE event_type = 'cart')     AS t_cart,
       MIN(event_time) FILTER (WHERE event_type = 'purchase') AS t_purchase
FROM events_clean
GROUP BY user_id;

-- Проверка
SELECT COUNT(*) FROM user_funnel;

-- Общая воронка
SELECT step, users,
       ROUND(100.0 * users / FIRST_VALUE(users) OVER (ORDER BY step_no), 2)  AS pct_of_first,
       ROUND(100.0 * users / LAG(users) OVER (ORDER BY step_no), 2)          AS conv_from_prev,
       ROUND(100.0 - 100.0 * users / LAG(users) OVER (ORDER BY step_no), 2)  AS loss_from_prev
FROM (
    SELECT 1 AS step_no, '1. view' AS step,
           COUNT(*) FILTER (WHERE t_view IS NOT NULL) AS users
    FROM user_funnel
    UNION ALL
    SELECT 2, '2. cart',
           COUNT(*) FILTER (WHERE t_cart >= t_view)
    FROM user_funnel
    UNION ALL
    SELECT 3, '3. purchase',
           COUNT(*) FILTER (WHERE t_purchase >= t_cart AND t_cart >= t_view)
    FROM user_funnel
) f
ORDER BY step_no;

-- Проверка логики порядка шагов
SELECT
    COUNT(*)                                                          AS all_users,
    COUNT(*) FILTER (WHERE t_view IS NULL)                            AS no_view,
    COUNT(*) FILTER (WHERE t_cart IS NOT NULL AND t_view IS NULL)     AS cart_without_view,
    COUNT(*) FILTER (WHERE t_purchase IS NOT NULL AND t_cart IS NULL) AS purchase_without_cart,
    COUNT(*) FILTER (WHERE t_cart < t_view)                           AS cart_before_view,
    COUNT(*) FILTER (WHERE t_purchase < t_cart)                       AS purchase_before_cart
FROM user_funnel;

-- Воронка по категориям
WITH user_cat AS (
    SELECT user_id,
           COALESCE(NULLIF(split_part(category_code, '.', 1), ''), 'unknown') AS category,
           MIN(event_time) FILTER (WHERE event_type = 'view')     AS t_view,
           MIN(event_time) FILTER (WHERE event_type = 'cart')     AS t_cart,
           MIN(event_time) FILTER (WHERE event_type = 'purchase') AS t_purchase
    FROM events_clean
    GROUP BY user_id, 2
)
SELECT category,
       COUNT(*) FILTER (WHERE t_view IS NOT NULL)                          AS viewers,
       COUNT(*) FILTER (WHERE t_cart >= t_view)                            AS carted,
       COUNT(*) FILTER (WHERE t_purchase >= t_cart AND t_cart >= t_view)   AS purchased,
       ROUND(100.0 * COUNT(*) FILTER (WHERE t_cart >= t_view)
             / NULLIF(COUNT(*) FILTER (WHERE t_view IS NOT NULL), 0), 2)   AS view_to_cart_pct,
       ROUND(100.0 * COUNT(*) FILTER (WHERE t_purchase >= t_cart AND t_cart >= t_view)
             / NULLIF(COUNT(*) FILTER (WHERE t_cart >= t_view), 0), 2)     AS cart_to_purchase_pct
FROM user_cat
GROUP BY category
HAVING COUNT(*) FILTER (WHERE t_view IS NOT NULL) >= 1000
ORDER BY viewers DESC;

-- Воронка по топ-20 брендам
SELECT ROUND(100.0 * COUNT(*) FILTER (WHERE brand = 'unknown') / COUNT(*), 2) AS brand_unknown_pct
FROM events_clean;

WITH top_brands AS (
    SELECT brand
    FROM events_clean
    WHERE brand <> 'unknown' AND event_type = 'view'
    GROUP BY brand
    ORDER BY COUNT(*) DESC
    LIMIT 20
),
user_brand AS (
    SELECT e.user_id, e.brand,
           MIN(e.event_time) FILTER (WHERE e.event_type = 'view')     AS t_view,
           MIN(e.event_time) FILTER (WHERE e.event_type = 'cart')     AS t_cart,
           MIN(e.event_time) FILTER (WHERE e.event_type = 'purchase') AS t_purchase
    FROM events_clean e
    JOIN top_brands tb ON tb.brand = e.brand
    GROUP BY e.user_id, e.brand
)
SELECT brand,
       COUNT(*) FILTER (WHERE t_view IS NOT NULL)                          AS viewers,
       COUNT(*) FILTER (WHERE t_cart >= t_view)                            AS carted,
       COUNT(*) FILTER (WHERE t_purchase >= t_cart AND t_cart >= t_view)   AS purchased,
       ROUND(100.0 * COUNT(*) FILTER (WHERE t_cart >= t_view)
             / NULLIF(COUNT(*) FILTER (WHERE t_view IS NOT NULL), 0), 2)   AS view_to_cart_pct,
       ROUND(100.0 * COUNT(*) FILTER (WHERE t_purchase >= t_cart AND t_cart >= t_view)
             / NULLIF(COUNT(*) FILTER (WHERE t_cart >= t_view), 0), 2)     AS cart_to_purchase_pct
FROM user_brand
GROUP BY brand
ORDER BY viewers DESC;

-- Средние цены по топ-брендам 
SELECT brand,
       COUNT(*)                                          AS views,
       ROUND(AVG(price) FILTER (WHERE price_valid), 2)   AS avg_price,
       ROUND(percentile_cont(0.5) WITHIN GROUP (ORDER BY price)
             FILTER (WHERE price_valid)::numeric, 2)     AS median_price
FROM events_clean
WHERE event_type = 'view'
  AND brand IN ('runail','irisk','grattol','estel','kapous','masura','jessnail','concept',
                'ingarden','uno','italwax','bpw.style','cnd','domix','bluesky','milv',
                'freedecor','pole')
GROUP BY brand
ORDER BY avg_price DESC;

-- 4.5. Воронка по месяцам первого визита
SELECT DATE_TRUNC('month', first_seen)::date AS cohort_month,
       COUNT(*) FILTER (WHERE t_view IS NOT NULL)                                   AS viewers,
       COUNT(*) FILTER (WHERE t_cart >= t_view)                                     AS carted,
       COUNT(*) FILTER (WHERE t_purchase >= t_cart AND t_cart >= t_view)            AS purchased,
       ROUND(100.0 * COUNT(*) FILTER (WHERE t_cart >= t_view)
             / NULLIF(COUNT(*) FILTER (WHERE t_view IS NOT NULL), 0), 2)            AS view_to_cart_pct,
       ROUND(100.0 * COUNT(*) FILTER (WHERE t_purchase >= t_cart AND t_cart >= t_view)
             / NULLIF(COUNT(*) FILTER (WHERE t_cart >= t_view), 0), 2)              AS cart_to_purchase_pct
FROM user_funnel
GROUP BY 1
ORDER BY 1;

-- 4.6. Время от корзины до покупки (в часах)
SELECT ROUND(percentile_cont(0.25) WITHIN GROUP (ORDER BY h)::numeric, 2) AS p25_hours,
       ROUND(percentile_cont(0.50) WITHIN GROUP (ORDER BY h)::numeric, 2) AS median_hours,
       ROUND(percentile_cont(0.75) WITHIN GROUP (ORDER BY h)::numeric, 2) AS p75_hours,
       ROUND(percentile_cont(0.90) WITHIN GROUP (ORDER BY h)::numeric, 2) AS p90_hours
FROM (
    SELECT EXTRACT(EPOCH FROM (t_purchase - t_cart)) / 3600.0 AS h
    FROM user_funnel
    WHERE t_purchase >= t_cart AND t_cart >= t_view
) t;
