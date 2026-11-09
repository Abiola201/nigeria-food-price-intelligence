-- Project 2: Nigeria Agricultural Market & Food Price Intelligence
-- Views that feed the Power BI dashboard (PostgreSQL)
-- Run the whole file once in pgAdmin (select all, F5). It is safe to run again: every statement is CREATE OR REPLACE.
-- Each bi_ view is the tested query from 02_analysis_queries.sql, shaped as a table Power BI can load.
-- Percentages are returned as fractions (7.41 means +741%) so Power BI can format them as percentages.

-- ---------------------------------------------------------------------
-- Base views (same as in 02_analysis_queries.sql)
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_fews AS
SELECT * FROM fews_prices WHERE COALESCE(outlier_flag, '') = '';

CREATE OR REPLACE VIEW v_monthly_market AS
SELECT market, state, zone, product, category, price_type, product_source, unit_standard,
       date_trunc('month', price_date)::date AS month,
       AVG(price_standard)                    AS price,
       COUNT(*)                               AS readings
FROM v_fews
GROUP BY market, state, zone, product, category, price_type, product_source, unit_standard,
         date_trunc('month', price_date);

CREATE OR REPLACE VIEW v_retail_kg AS
SELECT * FROM v_monthly_market
WHERE price_type = 'Retail' AND unit_standard = 'NGN per kg';

-- ---------------------------------------------------------------------
-- Dimension: products (Power BI relates every bi_ table to this by product)
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW bi_dim_product AS
SELECT DISTINCT product, category FROM v_fews;

-- ---------------------------------------------------------------------
-- Q6  Monthly trend: retail price per kg, national average of markets
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW bi_monthly_trend AS
SELECT month, product,
       ROUND(AVG(price), 2)    AS avg_price_ngn_per_kg,
       COUNT(DISTINCT market)  AS markets
FROM v_retail_kg
GROUP BY month, product;

-- ---------------------------------------------------------------------
-- Q7a  Price change, Jan-Sep 2019 vs Jan-Sep 2024, median of matched markets
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW bi_price_change AS
WITH y AS (
    SELECT market, product, EXTRACT(year FROM month)::int AS yr, AVG(price) AS p
    FROM v_retail_kg
    WHERE EXTRACT(year FROM month) IN (2019, 2024) AND EXTRACT(month FROM month) <= 9
    GROUP BY market, product, EXTRACT(year FROM month)
), pv AS (
    SELECT market, product,
           MAX(p) FILTER (WHERE yr = 2019) AS p19,
           MAX(p) FILTER (WHERE yr = 2024) AS p24
    FROM y
    GROUP BY market, product
    HAVING COUNT(*) = 2
)
SELECT product,
       COUNT(*)                                                                       AS matched_markets,
       ROUND(AVG(p19), 2)                                                             AS avg_price_2019,
       ROUND(AVG(p24), 2)                                                             AS avg_price_2024,
       ROUND((PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p24 / p19 - 1))::numeric, 4) AS median_change
FROM pv
GROUP BY product;

-- ---------------------------------------------------------------------
-- Q3a  Volatility: standard deviation of month-on-month change, Jan-19 onward
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW bi_volatility AS
WITH mm AS (
    SELECT market, product, month, price,
           LAG(price) OVER (PARTITION BY market, product ORDER BY month) AS prev_price,
           LAG(month) OVER (PARTITION BY market, product ORDER BY month) AS prev_month
    FROM v_retail_kg
    WHERE month >= DATE '2019-01-01'
), chg AS (
    SELECT product, month, AVG(price / prev_price - 1) AS mom
    FROM mm
    WHERE prev_month = (month - INTERVAL '1 month')::date
    GROUP BY product, month
)
SELECT product,
       ROUND(STDDEV_SAMP(mom)::numeric, 4) AS volatility,
       ROUND(AVG(mom)::numeric, 4)         AS avg_monthly_change,
       COUNT(*)                            AS months
FROM chg
GROUP BY product;

-- ---------------------------------------------------------------------
-- Q4  Retail markup over wholesale, matched market-months, by year
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW bi_retail_wholesale AS
WITH r AS (
    SELECT market, product, unit_standard, month, price FROM v_monthly_market WHERE price_type = 'Retail'
), w AS (
    SELECT market, product, unit_standard, month, price FROM v_monthly_market WHERE price_type = 'Wholesale'
)
SELECT EXTRACT(year FROM r.month)::int AS year,
       r.product, r.unit_standard,
       COUNT(*)                                       AS matched_market_months,
       ROUND(AVG(w.price), 2)                         AS avg_wholesale,
       ROUND(AVG(r.price), 2)                         AS avg_retail,
       ROUND((AVG(r.price / w.price) - 1)::numeric, 4) AS retail_markup
FROM r JOIN w USING (market, product, unit_standard, month)
GROUP BY EXTRACT(year FROM r.month), r.product, r.unit_standard;

-- ---------------------------------------------------------------------
-- Q9a  Local (milled) vs imported (5% broken) rice, retail per kg
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW bi_rice_premium AS
WITH l AS (SELECT market, month, price FROM v_retail_kg WHERE product = 'Rice (Milled)'),
     i AS (SELECT market, month, price FROM v_retail_kg WHERE product = 'Rice (5% Broken)')
SELECT EXTRACT(year FROM month)::int AS year,
       COUNT(*)                                          AS matched_market_months,
       ROUND(AVG(l.price), 2)                            AS local_ngn_per_kg,
       ROUND(AVG(i.price), 2)                            AS imported_ngn_per_kg,
       ROUND((AVG(i.price / l.price) - 1)::numeric, 4)   AS import_premium
FROM l JOIN i USING (market, month)
GROUP BY EXTRACT(year FROM month);

-- ---------------------------------------------------------------------
-- Q2a  States ranked across 13 staples, 2024 (avg_rank_share near 0 = priciest)
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW bi_state_rank AS
WITH sp AS (
    SELECT state, zone, product, AVG(price) AS p
    FROM v_retail_kg
    WHERE EXTRACT(year FROM month) = 2024
    GROUP BY state, zone, product
), ranked AS (
    SELECT state, zone, product,
           RANK() OVER (PARTITION BY product ORDER BY p DESC) AS rnk,
           COUNT(*) OVER (PARTITION BY product)               AS n_states
    FROM sp
)
SELECT state, zone,
       COUNT(*)                                AS products_covered,
       ROUND(AVG(rnk::numeric / n_states), 4)  AS avg_rank_share
FROM ranked
GROUP BY state, zone;

-- ---------------------------------------------------------------------
-- Q8  Zone price index, 2024 (100 = typical)
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW bi_zone_index AS
WITH zp AS (
    SELECT zone, product, AVG(price) AS p
    FROM v_retail_kg WHERE EXTRACT(year FROM month) = 2024
    GROUP BY zone, product
), np AS (
    SELECT product, AVG(price) AS p
    FROM v_retail_kg WHERE EXTRACT(year FROM month) = 2024
    GROUP BY product
)
SELECT zp.zone,
       COUNT(*)                                  AS products_covered,
       ROUND(AVG(zp.p / np.p) * 100, 1)          AS price_index
FROM zp JOIN np USING (product)
GROUP BY zp.zone;

-- ---------------------------------------------------------------------
-- Q5  Gap between the cheapest and priciest state, retail per kg, 2024
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW bi_state_gap AS
WITH sp AS (
    SELECT product, state, AVG(price) AS p
    FROM v_retail_kg WHERE EXTRACT(year FROM month) = 2024
    GROUP BY product, state
)
SELECT product,
       COUNT(*)                              AS states,
       ROUND(MIN(p), 2)                      AS lowest_price,
       (ARRAY_AGG(state ORDER BY p ASC))[1]  AS lowest_state,
       ROUND(MAX(p), 2)                      AS highest_price,
       (ARRAY_AGG(state ORDER BY p DESC))[1] AS highest_state,
       ROUND(MAX(p) / MIN(p), 2)             AS highest_to_lowest_ratio
FROM sp
GROUP BY product
HAVING COUNT(*) >= 5;

-- ---------------------------------------------------------------------
-- Q10a  Livestock: median price per head by year
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW bi_livestock_year AS
SELECT product, EXTRACT(year FROM price_date)::int AS year,
       ROUND((PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price_standard))::numeric, 0) AS median_price_per_head,
       COUNT(DISTINCT market) AS markets,
       COUNT(*)               AS readings
FROM v_fews
WHERE category = 'Livestock'
GROUP BY product, EXTRACT(year FROM price_date);

-- ---------------------------------------------------------------------
-- Q10b  Livestock: median price per head by state, 2024
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW bi_livestock_state AS
WITH s AS (
    SELECT product, state, zone,
           PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price_standard) AS med,
           COUNT(DISTINCT market) AS markets
    FROM v_fews
    WHERE category = 'Livestock' AND EXTRACT(year FROM price_date) = 2024
    GROUP BY product, state, zone
)
SELECT product, state, zone,
       ROUND(med::numeric, 0) AS median_price_per_head,
       markets,
       RANK() OVER (PARTITION BY product ORDER BY med DESC) AS rank_priciest
FROM s;

-- ---------------------------------------------------------------------
-- Q10c  Livestock change, Mar-Sep 2021 vs Mar-Sep 2024, matched markets
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW bi_livestock_change AS
WITH y AS (
    SELECT market, product, EXTRACT(year FROM month)::int AS yr, AVG(price) AS p
    FROM v_monthly_market
    WHERE category = 'Livestock'
      AND EXTRACT(year FROM month) IN (2021, 2024) AND EXTRACT(month FROM month) BETWEEN 3 AND 9
    GROUP BY market, product, EXTRACT(year FROM month)
), pv AS (
    SELECT market, product,
           MAX(p) FILTER (WHERE yr = 2021) AS p21,
           MAX(p) FILTER (WHERE yr = 2024) AS p24
    FROM y GROUP BY market, product HAVING COUNT(*) = 2
)
SELECT product,
       COUNT(*)           AS matched_markets,
       ROUND(AVG(p21), 0) AS avg_price_2021,
       ROUND(AVG(p24), 0) AS avg_price_2024,
       ROUND((PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p24 / p21 - 1))::numeric, 4) AS median_change
FROM pv
GROUP BY product;

-- ---------------------------------------------------------------------
-- Q11  Livestock seasonality: month average / that year's average x 100
-- 2022 and 2023 are full years; 2024 holds Jan-Sep only, so its index is against the Jan-Sep average.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW bi_livestock_seasonality AS
WITH m AS (
    SELECT product, EXTRACT(year FROM month)::int AS yr, EXTRACT(month FROM month)::int AS month_no, AVG(price) AS p
    FROM v_monthly_market
    WHERE category = 'Livestock' AND EXTRACT(year FROM month) IN (2022, 2023, 2024)
    GROUP BY product, EXTRACT(year FROM month), EXTRACT(month FROM month)
), y AS (
    SELECT product, yr, AVG(p) AS yp FROM m GROUP BY product, yr
)
SELECT m.product, m.yr AS year, m.month_no,
       ROUND((m.p / y.yp * 100)::numeric, 1) AS price_index
FROM m JOIN y USING (product, yr);

-- ---------------------------------------------------------------------
-- Q12  NBS: each item's price indexed to Jan-17 = 100
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW bi_nbs_index AS
WITH base AS (
    SELECT item, price_ngn AS b FROM nbs_prices WHERE price_month = DATE '2017-01-01'
)
SELECT n.item, n.category, n.animal_product,
       CASE WHEN n.animal_product = 'Yes' THEN 'Animal products' ELSE 'Plant foods and oils' END AS food_group,
       n.price_month,
       ROUND((n.price_ngn / base.b * 100)::numeric, 1) AS price_index
FROM nbs_prices n JOIN base USING (item);
