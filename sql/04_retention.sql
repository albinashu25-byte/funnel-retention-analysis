SET TIME ZONE 'UTC';

-- Таблица «пользователь x неделя активности»
DROP TABLE IF EXISTS user_weeks;

CREATE TABLE user_weeks AS
SELECT DISTINCT
       user_id,
       event_date - (EXTRACT(ISODOW FROM event_date)::int - 1) AS activity_week
FROM events_clean;

CREATE INDEX idx_user_weeks_user ON user_weeks(user_id);

-- Активные пользователи по неделям
SELECT activity_week, COUNT(*) AS active_users
FROM user_weeks
GROUP BY 1
ORDER BY 1;

-- Границы полных недель
DROP TABLE IF EXISTS week_bounds;

CREATE TABLE week_bounds AS
SELECT
    CASE WHEN EXTRACT(ISODOW FROM MIN(event_date)) = 1
         THEN MIN(event_date)
         ELSE MIN(event_date) + (8 - EXTRACT(ISODOW FROM MIN(event_date))::int)
    END AS first_full_week,
    CASE WHEN EXTRACT(ISODOW FROM MAX(event_date)) = 7
         THEN MAX(event_date) - 6
         ELSE MAX(event_date) - EXTRACT(ISODOW FROM MAX(event_date))::int - 6
    END AS last_full_week
FROM events_clean;

SELECT * FROM week_bounds;

-- Когорты
DROP TABLE IF EXISTS user_cohort;

CREATE TABLE user_cohort AS
SELECT user_id, MIN(activity_week) AS cohort_week
FROM user_weeks
GROUP BY user_id;

CREATE INDEX idx_user_cohort_user ON user_cohort(user_id);

-- Размеры когорт.
SELECT cohort_week, COUNT(*) AS cohort_size
FROM user_cohort
GROUP BY 1
ORDER BY 1;

-- Retention по когортам
DROP TABLE IF EXISTS cohort_retention;

CREATE TABLE cohort_retention AS
WITH b AS (
    SELECT first_full_week, last_full_week FROM week_bounds
),
cohort_users AS (
    SELECT uc.user_id, uc.cohort_week
    FROM user_cohort uc
    CROSS JOIN b
    WHERE uc.cohort_week >  b.first_full_week
      AND uc.cohort_week <= b.last_full_week
),
activity AS (
    SELECT cu.cohort_week,
           (uw.activity_week - cu.cohort_week) / 7 AS week_n,
           COUNT(*)                                AS active_users
    FROM cohort_users cu
    JOIN user_weeks uw ON uw.user_id = cu.user_id
    CROSS JOIN b
    WHERE uw.activity_week <= b.last_full_week
    GROUP BY 1, 2
)
SELECT cohort_week,
       week_n,
       active_users,
       FIRST_VALUE(active_users) OVER (PARTITION BY cohort_week ORDER BY week_n) AS cohort_size,
       ROUND(100.0 * active_users /
             FIRST_VALUE(active_users) OVER (PARTITION BY cohort_week ORDER BY week_n), 2) AS retention_pct
FROM activity;

-- Проверка
SELECT cohort_week, week_n, active_users, retention_pct
FROM cohort_retention
WHERE week_n = 0
ORDER BY cohort_week;

-- Когортная матрица
SELECT cohort_week,
       MAX(cohort_size) AS cohort_size,
       MAX(retention_pct) FILTER (WHERE week_n = 1) AS w1,
       MAX(retention_pct) FILTER (WHERE week_n = 2) AS w2,
       MAX(retention_pct) FILTER (WHERE week_n = 3) AS w3,
       MAX(retention_pct) FILTER (WHERE week_n = 4) AS w4,
       MAX(retention_pct) FILTER (WHERE week_n = 5) AS w5,
       MAX(retention_pct) FILTER (WHERE week_n = 6) AS w6,
       MAX(retention_pct) FILTER (WHERE week_n = 7) AS w7,
       MAX(retention_pct) FILTER (WHERE week_n = 8) AS w8
FROM cohort_retention
GROUP BY cohort_week
ORDER BY cohort_week;

-- Какая когорта отстает
WITH w AS (
    SELECT cohort_week, week_n, cohort_size, retention_pct
    FROM cohort_retention
    WHERE week_n IN (1, 2, 4)
      AND cohort_size >= 50000
)
SELECT week_n,
       cohort_week,
       cohort_size,
       retention_pct,
       ROUND(AVG(retention_pct) OVER (PARTITION BY week_n), 2)                 AS avg_all,
       ROUND(retention_pct - AVG(retention_pct) OVER (PARTITION BY week_n), 2) AS diff_pp,
       RANK() OVER (PARTITION BY week_n ORDER BY retention_pct)                AS rank_from_lowest
FROM w
ORDER BY week_n, rank_from_lowest;

-- Динамика внутри первой когорты
SELECT cohort_week, week_n, retention_pct,
       ROUND(retention_pct - LAG(retention_pct) OVER (PARTITION BY cohort_week ORDER BY week_n), 2) AS delta_pp
FROM cohort_retention
WHERE cohort_week = (SELECT MIN(cohort_week) FROM cohort_retention)
ORDER BY week_n;

-- Качество первого визита по когортам
SELECT uc.cohort_week,
       COUNT(*) AS users,
       ROUND(100.0 * COUNT(*) FILTER (WHERE f.t_cart     < uc.cohort_week + 7) / COUNT(*), 2) AS cart_first_week_pct,
       ROUND(100.0 * COUNT(*) FILTER (WHERE f.t_purchase < uc.cohort_week + 7) / COUNT(*), 2) AS purchase_first_week_pct
FROM user_cohort uc
JOIN user_funnel f USING (user_id)
CROSS JOIN week_bounds b
WHERE uc.cohort_week >  b.first_full_week
  AND uc.cohort_week <= b.last_full_week
GROUP BY 1
ORDER BY 1;

-- Retention покупателей 
DROP TABLE IF EXISTS buyer_weeks;

CREATE TABLE buyer_weeks AS
SELECT DISTINCT user_id,
       event_date - (EXTRACT(ISODOW FROM event_date)::int - 1) AS activity_week
FROM events_clean
WHERE event_type = 'purchase';

WITH b AS (SELECT first_full_week, last_full_week FROM week_bounds),
cohorts AS (
    SELECT user_id, MIN(activity_week) AS cohort_week FROM buyer_weeks GROUP BY 1
),
activity AS (
    SELECT c.cohort_week,
           (bw.activity_week - c.cohort_week) / 7 AS week_n,
           COUNT(*) AS buyers
    FROM cohorts c
    JOIN buyer_weeks bw USING (user_id)
    CROSS JOIN b
    WHERE c.cohort_week > b.first_full_week
      AND c.cohort_week <= b.last_full_week
      AND bw.activity_week <= b.last_full_week
    GROUP BY 1, 2
)
SELECT cohort_week, week_n, buyers,
       ROUND(100.0 * buyers / FIRST_VALUE(buyers) OVER (PARTITION BY cohort_week ORDER BY week_n), 2) AS repeat_purchase_pct
FROM activity
ORDER BY cohort_week, week_n;
