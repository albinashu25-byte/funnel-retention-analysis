SET TIME ZONE 'UTC';

-- 1. Сырая таблица.
CREATE TABLE events_raw (
    event_time    TEXT,
    event_type    TEXT,
    product_id    BIGINT,
    category_id   BIGINT,
    category_code TEXT,
    brand         TEXT,
    price         NUMERIC(10,2),
    user_id       BIGINT,
    user_session  TEXT
);

-- 2. Загрузка CSV
SELECT LEFT(event_time, 7) AS month, COUNT(*) AS events
FROM events_raw
GROUP BY 1
ORDER BY 1;

-- 3. Основная таблица с правильным типом даты.
DROP TABLE IF EXISTS events;

CREATE TABLE events AS
SELECT event_time::timestamptz AS event_time,
       event_type,
       product_id,
       category_code,
       brand,
       price,
       user_id
FROM events_raw;


CREATE INDEX idx_events_user ON events(user_id);
CREATE INDEX idx_events_time ON events(event_time);
CREATE INDEX idx_events_type ON events(event_type);


