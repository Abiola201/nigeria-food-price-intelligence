# Power BI build guide: Nigeria Agricultural Market & Food Price Intelligence

Everything here has been tested on the data except the Power BI clicks and DAX, which run on your computer. If a visual or measure shows an error, send me a screenshot.

## 0. Before you start
1. In pgAdmin, run `03_powerbi_views.sql` once (select all, F5). It creates the `bi_` views the dashboard uses.
2. Check it worked: `SELECT COUNT(*) FROM bi_monthly_trend;` should return 1521, and `SELECT COUNT(*) FROM bi_nbs_index;` should return 2537.
3. In Power BI Desktop: **View > Themes > Browse for themes** and pick `FoodPrice_Theme.json` (dark navy, gold and teal).

## 1. Load the data
**Home > Get data > PostgreSQL database**. Server `localhost`, database `food_prices`, Import mode. Tick these 17 items, then click **Transform Data**:

| Tick | Rename to |
| --- | --- |
| v_fews | FEWS_Prices |
| nbs_prices | NBS_Prices |
| state_zone | State_Zone |
| bi_dim_product | Dim_Product |
| bi_monthly_trend, bi_price_change, bi_volatility, bi_retail_wholesale, bi_rice_premium, bi_state_rank, bi_zone_index, bi_state_gap, bi_livestock_year, bi_livestock_state, bi_livestock_change, bi_livestock_seasonality, bi_nbs_index | keep the names |

In Power Query, check these column types, then **Close & Apply**:
- `FEWS_Prices[price_date]` = Date; `price_standard`, `latitude`, `longitude` = Decimal Number; `year` and `month_no` = Whole Number.
- `bi_monthly_trend[month]` = Date; `bi_nbs_index[price_month]` = Date.
- `NBS_Prices[price_month]` = Date.

## 2. Model (Model view)
Create these relationships, all **many-to-one, single direction** (many side is the table on the left):

| From (many) | To (one) |
| --- | --- |
| FEWS_Prices[product], bi_monthly_trend[product], bi_price_change[product], bi_volatility[product], bi_retail_wholesale[product], bi_state_gap[product], bi_livestock_year[product], bi_livestock_state[product], bi_livestock_change[product], bi_livestock_seasonality[product] | Dim_Product[product] |
| FEWS_Prices[state], bi_state_rank[state], bi_livestock_state[state] | State_Zone[state] |

Leave `NBS_Prices`, `bi_nbs_index`, `bi_zone_index` and `bi_rice_premium` unconnected. Never connect any NBS table to a FEWS table.

## 3. DAX measures
Select any table, then **Home > New measure** for each. Put them all in `FEWS_Prices` or a blank table called `Measures`.

```dax
Readings        = COUNTROWS ( FEWS_Prices )
Markets         = DISTINCTCOUNT ( FEWS_Prices[market] )
States Covered  = DISTINCTCOUNT ( FEWS_Prices[state] )
Avg Price       = AVERAGE ( FEWS_Prices[price_standard] )
Avg Retail Price = AVERAGE ( bi_monthly_trend[avg_price_ngn_per_kg] )

Biggest Rise    = MAX ( bi_price_change[median_change] )
Biggest Riser   = MAXX ( TOPN ( 1, bi_price_change, bi_price_change[median_change], DESC ), bi_price_change[product] )
Most Volatile   = MAXX ( TOPN ( 1, bi_volatility, bi_volatility[volatility], DESC ), bi_volatility[product] )
Priciest State  = MAXX ( TOPN ( 1, bi_state_rank, bi_state_rank[avg_rank_share], ASC ), bi_state_rank[state] )

Retail Markup   = AVERAGE ( bi_retail_wholesale[retail_markup] )
Rice Premium 2024 = CALCULATE ( MAX ( bi_rice_premium[import_premium] ), bi_rice_premium[year] = 2024 )

Goat Change     = CALCULATE ( MAX ( bi_livestock_change[median_change] ), bi_livestock_change[product] = "Goats (Male)" )
Cattle Change   = CALCULATE ( MAX ( bi_livestock_change[median_change] ), bi_livestock_change[product] = "Cattle (Male)" )
Sheep Change    = CALCULATE ( MAX ( bi_livestock_change[median_change] ), bi_livestock_change[product] = "Sheep (Male)" )

Median Livestock Price = AVERAGE ( bi_livestock_year[median_price_per_head] )
Livestock State Price  = AVERAGE ( bi_livestock_state[median_price_per_head] )
Seasonal Index         = AVERAGE ( bi_livestock_seasonality[price_index] )
Food Price Index       = AVERAGE ( bi_nbs_index[price_index] )
Volatility (pts)       = AVERAGE ( bi_volatility[volatility] )
Zone Index             = AVERAGE ( bi_zone_index[price_index] )
Gap Ratio              = AVERAGE ( bi_state_gap[highest_to_lowest_ratio] )
```

Formats: set `Biggest Rise`, `Retail Markup`, `Rice Premium 2024`, `Goat/Cattle/Sheep Change` and `Volatility (pts)` to **Percentage, 0 decimals**. `Avg Price` and `Avg Retail Price` to **Currency (₦), 0 decimals**. `Median Livestock Price` and `Livestock State Price` to whole numbers with thousands separators.

## 4. Pages
Add this footer text box to every page: *Sources: FEWS NET (HDX) and NBS Food Prices 2017-2021. Prices are nominal naira. FEWS NET covers 15 states, mostly in the north, so figures describe the markets monitored.*

### Page 1: Overview
- **Page filters:** none needed (the bi_ tables are already prepared).
- **Cards (top row):** `Biggest Rise` (title "Biggest staple price rise, 2019 to 2024"), `Biggest Riser`, `Rice Premium 2024`, `Markets`.
- **Bar chart:** axis `bi_price_change[product]`, values `bi_price_change[median_change]` (Average), sorted high to low. Title: "Median change in retail price per kg, Jan-Sep 2019 to Jan-Sep 2024".
- **Slicer:** `Dim_Product[category]`.
- **Cards (second row):** `Goat Change`, `Cattle Change`, `Sheep Change` (title "Livestock price change, 2021 to 2024").

### Page 2: Market Comparison
- **Map:** location `FEWS_Prices[market]` with latitude and longitude, bubble size `Avg Price`. Add a visual-level filter `FEWS_Prices[unit_standard]` = NGN per kg and `price_type` = Retail, plus a single-select slicer on `Dim_Product[product]`.
- **Column chart:** axis `bi_zone_index[zone]`, values `Zone Index`, add a constant line at 100. Title: "Price index by zone, 2024 (100 = typical)".
- **Bar chart:** axis `bi_state_gap[product]`, values `Gap Ratio`. Title: "Priciest state vs cheapest state, 2024".
- **Clustered column:** axis `bi_retail_wholesale[product]`, values `Retail Markup`, with a slicer on `bi_retail_wholesale[year]` (set to 2024). Title: "Retail markup over wholesale".
- **Line chart:** axis `bi_rice_premium[year]`, values `local_ngn_per_kg` and `imported_ngn_per_kg`. Title: "Local vs imported rice, per kg".
- **Card:** `Priciest State`.

### Page 3: Livestock
- **Slicer (single select):** `Dim_Product[product]`, filtered to the three livestock products using a visual-level filter on `Dim_Product[category]` = Livestock.
- **Line chart:** axis `bi_livestock_year[year]`, values `Median Livestock Price`, legend `product`. Title: "Median price per animal, by year".
- **Bar chart:** axis `bi_livestock_state[state]`, values `Livestock State Price`, sorted high to low. Title: "Median price per animal by state, 2024".
- **Line chart:** axis `bi_livestock_seasonality[month_no]`, values `Seasonal Index`, legend `year`, constant line at 100. Select Sheep. Title: "Sheep price index by month (year average = 100)". Add a text note: "Peaks in the month of Eid al-Adha: Jul 2022, Jun 2023, Jun 2024. 2024 covers Jan-Sep only."
- **Cards:** `Goat Change`, `Cattle Change`, `Sheep Change`.

### Page 4: Trends and Volatility
- **Slicer:** `Dim_Product[product]` (multi-select).
- **Line chart:** axis `bi_monthly_trend[month]`, values `Avg Retail Price`, legend `product`. Title: "Monthly retail price per kg".
- **Bar chart:** axis `bi_volatility[product]`, values `Volatility (pts)`, sorted high to low. Title: "Month-on-month volatility, 2019 to 2024".
- **Card:** `Most Volatile`.

### Page 5: Animal Products vs Plant Foods (NBS)
- **Line chart:** axis `bi_nbs_index[price_month]`, values `Food Price Index`, legend `food_group`, constant line at 100. Title: "Price index, Jan 2017 = 100".
- **Bar chart:** axis `bi_nbs_index[category]`, values `Food Price Index`, with a visual-level filter `price_month` = 1 Nov 2021. Title: "Index by category, Nov 2021".
- **Slicer:** `bi_nbs_index[item]`.

## 5. Quick checks before you screenshot
| Check | Expected |
| --- | --- |
| Biggest Rise card | 741% |
| Biggest Riser card | Sorghum (Brown) |
| Rice Premium 2024 | 32% |
| Goat / Cattle / Sheep change | 100% / 92% / 73% |
| Zone index | South West 118, South East 112, North East 99, North West 93 |
| Most Volatile | Cowpeas (White) |
| Priciest State | Lagos |
| NBS index, Nov 2021 | Plant foods and oils 147, Animal products 136 |

If a number differs, check that the relationships in section 2 are one-to-many with single direction and that no slicer is filtering the page.
