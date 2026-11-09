-- Project 2: Nigeria Agricultural Market & Food Price Intelligence
-- Step 1: create tables  |  Step 2: import the three CSV files  |  Step 3: verify

-- ------------------------------------------------------------------
-- STEP 1. Create tables (run in pgAdmin Query Tool or psql)
-- Column order matches the CSV files exactly, so no column list is needed on import.
-- ------------------------------------------------------------------
DROP TABLE IF EXISTS fews_prices;
DROP TABLE IF EXISTS nbs_prices;
DROP TABLE IF EXISTS state_zone;

CREATE TABLE state_zone (
    state  text PRIMARY KEY,
    zone   text NOT NULL
);

CREATE TABLE nbs_prices (
    item            text    NOT NULL,
    category        text    NOT NULL,
    animal_product  text,
    price_month     date    NOT NULL,
    year            int,
    month_no        int,
    price_ngn       numeric NOT NULL,   -- naira, nominal
    mom_pct         numeric,            -- month-on-month change, blank for Jan-17
    spike_flag      text                -- 'Review' where the move is above 35%
);

CREATE TABLE fews_prices (
    market          text,
    state           text,
    zone            text,
    latitude        numeric,
    longitude       numeric,
    product         text,
    category        text,
    price_type      text,               -- Retail / Wholesale
    product_source  text,               -- Local / Import
    price_date      date,
    year            int,
    month_no        int,
    unit_original   text,
    price_original  numeric,
    unit_standard   text,               -- NGN per kg / litre / item / tuber
    price_standard  numeric,
    outlier_flag    text                -- 'High' / 'Low' / NULL
);

-- ------------------------------------------------------------------
-- STEP 2. Import
-- Option A (psql): edit the folder path, then run these three lines.
-- Use forward slashes on Windows. \copy reads the file from YOUR computer.
-- ------------------------------------------------------------------
-- \copy state_zone  FROM 'C:/Users/YourName/Downloads/state_zone_lookup.csv'  WITH (FORMAT csv, HEADER true)
-- \copy nbs_prices  FROM 'C:/Users/YourName/Downloads/nbs_prices_long.csv'    WITH (FORMAT csv, HEADER true)
-- \copy fews_prices FROM 'C:/Users/YourName/Downloads/fews_prices_clean.csv'  WITH (FORMAT csv, HEADER true)
--
-- Option B (pgAdmin): right-click each table > Import/Export Data...
--   Import, Format: csv, Header: on, Delimiter: comma, Quote: ", Escape: "
--   Pick the matching CSV file, then click OK.
--   Do not use the SQL COPY command here: it reads files on the server, not your computer.

-- ------------------------------------------------------------------
-- STEP 3. Verify, then add indexes
-- ------------------------------------------------------------------
SELECT 'state_zone'  AS table_name, COUNT(*) AS rows_loaded, 15     AS expected FROM state_zone
UNION ALL
SELECT 'nbs_prices',  COUNT(*), 2537   FROM nbs_prices
UNION ALL
SELECT 'fews_prices', COUNT(*), 228381 FROM fews_prices;

-- Livestock rows (expected 7064) and flagged outliers (expected 51)
SELECT COUNT(*) AS livestock_rows FROM fews_prices WHERE category = 'Livestock';
SELECT COUNT(*) AS outlier_rows   FROM fews_prices WHERE outlier_flag IS NOT NULL;

-- Spot check against the Excel Checks sheet: NBS local rice in Jun-17 should be 325.51
SELECT price_ngn FROM nbs_prices WHERE item = 'Rice, local (loose)' AND price_month = DATE '2017-06-01';

CREATE INDEX idx_fews_product_date ON fews_prices (product, price_date);
CREATE INDEX idx_fews_state        ON fews_prices (state);
CREATE INDEX idx_nbs_item_month    ON nbs_prices (item, price_month);
ANALYZE;
