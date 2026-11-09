-- Project 2: Nigeria Agricultural Market & Food Price Intelligence
-- Analysis queries for the 12 business questions (PostgreSQL)
-- Run the VIEWS section first, then run each query on its own (highlight it, then F5 in pgAdmin).
--
-- Rules used throughout
--   * All prices are nominal naira (not adjusted for inflation).
--   * Rows flagged as outliers are excluded (view v_fews).
--   * Market-level monthly averages are the base, so weekly reading counts do not distort results.
--   * Only compare prices in the same unit_standard. "Retail per kg" is the main comparable set.
--   * 2024 holds January to September only, so year-on-year comparisons use the same months in both years.

-- =====================================================================
-- VIEWS
-- =====================================================================
CREATE OR REPLACE VIEW v_fews AS
SELECT * FROM fews_prices WHERE COALESCE(outlier_flag, '') = '';   -- works whether blanks imported as NULL or as empty text

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

-- =====================================================================
-- Q1. Which commodities have the highest average prices?
-- =====================================================================
-- 1a. FEWS NET: average retail price per kg in 2024 (Jan-Sep)
SELECT product,
       ROUND(AVG(price), 2)        AS avg_retail_ngn_per_kg_2024,
       COUNT(DISTINCT market)      AS markets
FROM v_retail_kg
WHERE EXTRACT(year FROM month) = 2024
GROUP BY product
ORDER BY avg_retail_ngn_per_kg_2024 DESC;

-- 1b. NBS: ten highest average prices across Jan-17 to Nov-21 (units differ by item: kg, bottle, item)
SELECT item, category, ROUND(AVG(price_ngn), 2) AS avg_price_ngn
FROM nbs_prices
GROUP BY item, category
ORDER BY avg_price_ngn DESC
LIMIT 10;

-- =====================================================================
-- Q2. Which states and markets have the highest and lowest prices?
-- Method: rank states (or markets) within each product, then average the rank share.
-- avg_rank_share near 0 = among the most expensive; near 1 = among the cheapest.
-- =====================================================================
-- 2a. States, retail per kg, 2024
WITH sp AS (
    SELECT state, product, AVG(price) AS p
    FROM v_retail_kg
    WHERE EXTRACT(year FROM month) = 2024
    GROUP BY state, product
), ranked AS (
    SELECT state, product, p,
           RANK() OVER (PARTITION BY product ORDER BY p DESC) AS rnk,
           COUNT(*) OVER (PARTITION BY product)               AS n_states
    FROM sp
)
SELECT state,
       COUNT(*)                              AS products_covered,
       ROUND(AVG(rnk::numeric / n_states), 2) AS avg_rank_share,
       DENSE_RANK() OVER (ORDER BY AVG(rnk::numeric / n_states)) AS overall_rank_1_is_priciest
FROM ranked
GROUP BY state
ORDER BY avg_rank_share;

-- 2b. Markets, retail per kg, 2024 (only markets with at least 8 products)
WITH mp AS (
    SELECT market, state, product, AVG(price) AS p
    FROM v_retail_kg
    WHERE EXTRACT(year FROM month) = 2024
    GROUP BY market, state, product
), ranked AS (
    SELECT market, state, product,
           RANK() OVER (PARTITION BY product ORDER BY p DESC) AS rnk,
           COUNT(*) OVER (PARTITION BY product)               AS n_markets
    FROM mp
)
SELECT market, state,
       COUNT(*)                               AS products_covered,
       ROUND(AVG(rnk::numeric / n_markets), 2) AS avg_rank_share
FROM ranked
GROUP BY market, state
HAVING COUNT(*) >= 8
ORDER BY avg_rank_share;

-- =====================================================================
-- Q3. Which commodities fluctuate and swing most?
-- Volatility = standard deviation of month-on-month % change (removes the long-run trend).
-- =====================================================================
-- 3a. FEWS NET, retail per kg, Jan-19 to Sep-24
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
       ROUND(STDDEV_SAMP(mom) * 100, 2) AS volatility_pct_points,
       ROUND(AVG(mom) * 100, 2)         AS avg_mom_pct,
       COUNT(*)                         AS months
FROM chg
GROUP BY product
ORDER BY volatility_pct_points DESC;

-- 3b. NBS, all 43 items (spike_flag marks one-month moves above 35%)
SELECT item, category,
       ROUND(STDDEV_SAMP(mom_pct) * 100, 2)          AS volatility_pct_points,
       COUNT(*) FILTER (WHERE spike_flag = 'Review') AS spike_months
FROM nbs_prices
WHERE mom_pct IS NOT NULL
GROUP BY item, category
ORDER BY volatility_pct_points DESC
LIMIT 10;

-- =====================================================================
-- Q4. How do retail and wholesale prices compare?
-- Matched on the same market, product and month. Yams are excluded (retail per kg, wholesale per tuber).
-- =====================================================================
WITH r AS (
    SELECT market, product, unit_standard, month, price
    FROM v_monthly_market WHERE price_type = 'Retail'
), w AS (
    SELECT market, product, unit_standard, month, price
    FROM v_monthly_market WHERE price_type = 'Wholesale'
)
SELECT r.product, r.unit_standard,
       COUNT(*)                                      AS matched_market_months,
       ROUND(AVG(w.price), 2)                        AS avg_wholesale,
       ROUND(AVG(r.price), 2)                        AS avg_retail,
       ROUND(AVG(r.price / w.price - 1) * 100, 1)    AS retail_markup_pct
FROM r
JOIN w USING (market, product, unit_standard, month)
WHERE EXTRACT(year FROM r.month) = 2024
GROUP BY r.product, r.unit_standard
ORDER BY retail_markup_pct DESC;

-- =====================================================================
-- Q5. Which commodities differ most between states? (retail per kg, 2024)
-- =====================================================================
WITH sp AS (
    SELECT product, state, AVG(price) AS p
    FROM v_retail_kg
    WHERE EXTRACT(year FROM month) = 2024
    GROUP BY product, state
)
SELECT product,
       COUNT(*)                                   AS states,
       ROUND(MIN(p), 2)                           AS lowest_state_price,
       (ARRAY_AGG(state ORDER BY p ASC))[1]       AS lowest_state,
       ROUND(MAX(p), 2)                           AS highest_state_price,
       (ARRAY_AGG(state ORDER BY p DESC))[1]      AS highest_state,
       ROUND(MAX(p) - MIN(p), 2)                  AS gap_ngn,
       ROUND(MAX(p) / MIN(p), 2)                  AS highest_to_lowest_ratio
FROM sp
GROUP BY product
HAVING COUNT(*) >= 5
ORDER BY highest_to_lowest_ratio DESC;

-- =====================================================================
-- Q6. What are the monthly price trends? (feeds the Power BI trend page)
-- Preview with LIMIT 20; export the full result to CSV for Power BI if needed.
-- =====================================================================
SELECT month, product,
       ROUND(AVG(price), 2)        AS avg_retail_ngn_per_kg,
       COUNT(DISTINCT market)      AS markets
FROM v_retail_kg
GROUP BY month, product
ORDER BY product, month;

-- =====================================================================
-- Q7. Which commodities rose most, and which pose the biggest affordability challenge?
-- Median of market-level % change, only markets with data in both periods.
-- =====================================================================
-- 7a. FEWS NET, Jan-Sep 2019 vs Jan-Sep 2024, retail per kg
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
), agg AS (
    SELECT product,
           COUNT(*)                                                       AS matched_markets,
           ROUND(AVG(p19), 2)                                             AS avg_2019,
           ROUND(AVG(p24), 2)                                             AS avg_2024,
           ROUND((PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p24 / p19 - 1) * 100)::numeric, 0) AS median_change_pct
    FROM pv
    GROUP BY product
)
SELECT RANK() OVER (ORDER BY median_change_pct DESC) AS rank_biggest_rise, *
FROM agg
ORDER BY rank_biggest_rise;

-- 7b. NBS, 2017 vs 2021 (Jan-Nov of each year)
WITH y AS (
    SELECT item, category,
           AVG(price_ngn) FILTER (WHERE year = 2017) AS p17,
           AVG(price_ngn) FILTER (WHERE year = 2021) AS p21
    FROM nbs_prices
    WHERE month_no <= 11
    GROUP BY item, category
)
SELECT RANK() OVER (ORDER BY p21 / p17 DESC) AS rank_biggest_rise,
       item, category, ROUND(p17, 2) AS avg_2017, ROUND(p21, 2) AS avg_2021,
       ROUND((p21 / p17 - 1) * 100, 1) AS change_pct
FROM y
ORDER BY rank_biggest_rise
LIMIT 15;

-- =====================================================================
-- Q8. Which geopolitical zones are most expensive?
-- Price index: zone average / all-market average for each product, then averaged (100 = typical).
-- =====================================================================
WITH zp AS (
    SELECT zone, product, AVG(price) AS p
    FROM v_retail_kg
    WHERE EXTRACT(year FROM month) = 2024
    GROUP BY zone, product
), np AS (
    SELECT product, AVG(price) AS p
    FROM v_retail_kg
    WHERE EXTRACT(year FROM month) = 2024
    GROUP BY product
)
SELECT zp.zone,
       COUNT(*)                          AS products_covered,
       ROUND(AVG(zp.p / np.p) * 100, 1)  AS price_index_100_is_typical
FROM zp JOIN np USING (product)
GROUP BY zp.zone
ORDER BY price_index_100_is_typical DESC;

-- =====================================================================
-- Q9. How do local and imported rice compare?
-- =====================================================================
-- 9a. FEWS NET: milled (local) vs 5% broken (imported), retail per kg, matched market-months
WITH l AS (
    SELECT market, month, price FROM v_retail_kg WHERE product = 'Rice (Milled)'
), i AS (
    SELECT market, month, price FROM v_retail_kg WHERE product = 'Rice (5% Broken)'
)
SELECT EXTRACT(year FROM month)::int AS year,
       COUNT(*)                                    AS matched_market_months,
       ROUND(AVG(l.price), 2)                      AS local_ngn_per_kg,
       ROUND(AVG(i.price), 2)                      AS imported_ngn_per_kg,
       ROUND(AVG(i.price / l.price - 1) * 100, 1)  AS import_premium_pct
FROM l JOIN i USING (market, month)
GROUP BY EXTRACT(year FROM month)
ORDER BY year;

-- 9b. NBS: local vs imported high quality rice, annual average
SELECT year,
       ROUND(AVG(price_ngn) FILTER (WHERE item = 'Rice, local (loose)'), 2)                    AS local_loose,
       ROUND(AVG(price_ngn) FILTER (WHERE item = 'Rice, imported high quality (loose)'), 2)    AS imported_loose,
       ROUND((AVG(price_ngn) FILTER (WHERE item = 'Rice, imported high quality (loose)')
            / AVG(price_ngn) FILTER (WHERE item = 'Rice, local (loose)') - 1) * 100, 1)        AS import_premium_pct
FROM nbs_prices
WHERE item IN ('Rice, local (loose)', 'Rice, imported high quality (loose)')
GROUP BY year
ORDER BY year;

-- =====================================================================
-- Q10. How fast did cattle, goat and sheep prices rise, and which states pay most?
-- Price per animal (NGN per item), male animals only. Livestock data starts March 2021.
-- =====================================================================
-- 10a. Median price per head by year
SELECT product, EXTRACT(year FROM price_date)::int AS year,
       ROUND((PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price_standard))::numeric, 0) AS median_price_per_head,
       COUNT(DISTINCT market) AS markets,
       COUNT(*)               AS readings
FROM v_fews
WHERE category = 'Livestock'
GROUP BY product, EXTRACT(year FROM price_date)
ORDER BY product, year;

-- 10b. Median price per head by state in 2024, ranked
WITH s AS (
    SELECT product, state,
           PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price_standard) AS med,
           COUNT(DISTINCT market) AS markets
    FROM v_fews
    WHERE category = 'Livestock' AND EXTRACT(year FROM price_date) = 2024
    GROUP BY product, state
)
SELECT product, state, ROUND(med::numeric, 0) AS median_price_per_head, markets,
       RANK() OVER (PARTITION BY product ORDER BY med DESC) AS rank_1_is_priciest
FROM s
ORDER BY product, rank_1_is_priciest;

-- 10c. Change Mar-Sep 2021 to Mar-Sep 2024 (same months), markets with data in both
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
       COUNT(*)                         AS matched_markets,
       ROUND(AVG(p21), 0)               AS avg_2021,
       ROUND(AVG(p24), 0)               AS avg_2024,
       ROUND((PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p24 / p21 - 1) * 100)::numeric, 0) AS median_change_pct
FROM pv
GROUP BY product
ORDER BY median_change_pct DESC;

-- =====================================================================
-- Q11. Is there a seasonal pattern in livestock prices?
-- Index = month average / that year's average x 100, for the two full years 2022 and 2023.
-- Only two years of data: treat any pattern as a hypothesis, not a finding.
-- Prices trend upward, so later months read higher by default; a real seasonal peak
-- must appear in both years and in more than one animal.
-- =====================================================================
WITH m AS (
    SELECT product, EXTRACT(year FROM month)::int AS yr, EXTRACT(month FROM month)::int AS mo, AVG(price) AS p
    FROM v_monthly_market
    WHERE category = 'Livestock' AND EXTRACT(year FROM month) IN (2022, 2023)
    GROUP BY product, EXTRACT(year FROM month), EXTRACT(month FROM month)
), y AS (
    SELECT product, yr, AVG(p) AS yp FROM m GROUP BY product, yr
)
SELECT m.product, m.mo AS month_no,
       ROUND(AVG(m.p / y.yp * 100) FILTER (WHERE m.yr = 2022), 1) AS index_2022,
       ROUND(AVG(m.p / y.yp * 100) FILTER (WHERE m.yr = 2023), 1) AS index_2023
FROM m JOIN y USING (product, yr)
GROUP BY m.product, m.mo
ORDER BY m.product, m.mo;

-- =====================================================================
-- Q12. Did animal protein (eggs, beef, chicken, fish, milk) rise faster than staples? (NBS)
-- Index: each item's price / its Jan-17 price x 100, averaged across items.
-- =====================================================================
-- 12a. Animal products vs everything else
WITH base AS (
    SELECT item, price_ngn AS b FROM nbs_prices WHERE price_month = DATE '2017-01-01'
), idx AS (
    SELECT n.item, n.category, n.animal_product, n.price_month, n.price_ngn / base.b * 100 AS idx
    FROM nbs_prices n JOIN base USING (item)
)
SELECT CASE WHEN animal_product = 'Yes' THEN 'Animal products' ELSE 'Plant foods and oils' END AS group_name,
       COUNT(DISTINCT item)                                               AS items,
       ROUND(AVG(idx) FILTER (WHERE price_month = DATE '2019-01-01'), 1)  AS index_jan_2019,
       ROUND(AVG(idx) FILTER (WHERE price_month = DATE '2021-01-01'), 1)  AS index_jan_2021,
       ROUND(AVG(idx) FILTER (WHERE price_month = DATE '2021-11-01'), 1)  AS index_nov_2021
FROM idx
GROUP BY animal_product
ORDER BY index_nov_2021 DESC;

-- 12b. By category
WITH base AS (
    SELECT item, price_ngn AS b FROM nbs_prices WHERE price_month = DATE '2017-01-01'
), idx AS (
    SELECT n.item, n.category, n.price_month, n.price_ngn / base.b * 100 AS idx
    FROM nbs_prices n JOIN base USING (item)
)
SELECT category,
       COUNT(DISTINCT item)                                               AS items,
       ROUND(AVG(idx) FILTER (WHERE price_month = DATE '2021-11-01'), 1)  AS index_nov_2021
FROM idx
GROUP BY category
ORDER BY index_nov_2021 DESC;
