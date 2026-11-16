-- 04_views.sql: creates the three views used by the analysis (run after 03_validate.sql)
-- Layers: tables -> v_base (rules) -> v_specialism_year (KPIs per specialism) -> v_national_year (KPIs for the country)
--         and v_specialism_year -> v_specialism_growth (KPI 3: change and momentum per specialism)

-- Drop the views first so the file can be re-run from the top
-- (CREATE VIEW fails if the view already exists). Reverse order: last built, first dropped.
DROP VIEW IF EXISTS v_specialism_growth;
DROP VIEW IF EXISTS v_national_year;
DROP VIEW IF EXISTS v_specialism_year;
DROP VIEW IF EXISTS v_base;

-- v_base: one row per year x specialism x mapped activity code, 2019 to 2024.
-- Why it exists: every rule lives here once (the six mapped codes, their channel, the years
-- in scope), so no later view or query repeats them. Read by v_specialism_year, Q6 and Q7.
-- Built from: consult_volume, channel_map, specialism.
-- Expected rows: at most 810 (6 years x 27 specialisms x 5 codes). Actual: 734 (76 combinations
-- have no activity, mostly telemonitoring). Cross-check: total 114,525,564 = check 6.
CREATE VIEW v_base AS
SELECT cv.year,                -- start year of the treatment path
       cv.specialism_code,     -- which specialism
       s.specialism_name,      -- its Dutch name, from specialism
       cv.activity_code,       -- which of the six mapped codes
       cm.channel,             -- clinic, phone, video, written or telemonitoring
       cm.is_remote,           -- true = counts in the remote share
       cv.activity_count       -- how many times it happened
FROM consult_volume AS cv
JOIN channel_map AS cm ON cv.activity_code = cm.activity_code      -- keeps only the six mapped codes, adds the channel
JOIN specialism AS s ON cv.specialism_code = s.specialism_code     -- adds the specialism name
WHERE cv.year BETWEEN 2019 AND 2024;                               -- pre-COVID baseline to last full year, both ends included

-- Check v_base 1: total count. Expected: 114,525,564 (same as check 6 in 03_validate.sql)
SELECT SUM(activity_count) AS total_count
FROM v_base;

-- Check v_base 2: number of rows. Expected: 734
SELECT COUNT(*) AS row_count
FROM v_base;

-- v_specialism_year: one row per specialism per year, 2019 to 2024, with the KPI numbers.
-- Why it exists: KPIs 1, 2 and 3 (volume, remote share, growth) are calculated here once, so
-- every answer query uses the same definition. Telemonitoring is left out (rule 4).
-- Why telemonitoring is left out: it is a period of monitoring at home, not a visit, so it is
-- not a consult. Without the WHERE, clinic and remote would not change (their CASE already
-- gives 0 for telemonitoring), but all_consults would include it, and the remote share would
-- be divided by a total that is too big, so it would come out too low. Example: ophthalmology
-- 2024 would have 1,376,471 consults instead of 1,375,082 (1,389 telemonitoring). Telemonitoring
-- is still counted on its own (KPI 4, Q7), straight from v_base.
-- Read by v_national_year and Q2 to Q5, Q8 to Q10.
-- Built from: v_base.
-- Expected rows: at most 162 (6 years x 27 specialisms), minus the 3 specialism-years with no
-- clinic row in v_base = 159. Cross-check: all consults = 114,525,564 (v_base total)
-- minus 586,144 (telemonitoring) = 113,939,420.
CREATE VIEW v_specialism_year AS
SELECT year,
       specialism_code,
       specialism_name,
       SUM(CASE WHEN channel = 'clinic' THEN activity_count ELSE 0 END) AS clinic,   -- follow-up visits in the hospital
       SUM(CASE WHEN is_remote THEN activity_count ELSE 0 END) AS remote,            -- phone + video + written
       SUM(activity_count) AS all_consults,                                          -- clinic + remote (telemonitoring is filtered out below)
       ROUND(100.0 * SUM(CASE WHEN is_remote THEN activity_count ELSE 0 END)
                   / SUM(activity_count), 1) AS remote_share_pct                     -- 100.0 keeps the decimals (integer division gives 0)
FROM v_base                                                                          -- the rules are already applied there
WHERE channel <> 'telemonitoring'                                                    -- rule 4: telemonitoring is not a consult
GROUP BY year, specialism_code, specialism_name;                                     -- one row per specialism per year

-- Check v_specialism_year 1: number of rows. Expected: 159
SELECT COUNT(*) AS row_count
FROM v_specialism_year;

-- Check v_specialism_year 2: total of all consults. Expected: 113,939,420 (v_base total minus telemonitoring)
SELECT SUM(all_consults) AS total_consults
FROM v_specialism_year;

-- Check v_specialism_year 3: one row by hand. Ophthalmology (0301) 2024.
-- Expected: clinic 1,252,628, remote 122,454 (118,888 phone + 3,521 written + 45 video),
-- all 1,375,082, share 8.9 (from the five v_base rows seen earlier)
SELECT *
FROM v_specialism_year
WHERE year = 2024
  AND specialism_code = '0301';

-- v_national_year: one row per year for the whole country, 2019 to 2024.
-- Why it exists: the national benchmark every specialism is compared with (KPIs 2 and 3), and
-- the national trend (Q1). Rule 3: the national share is all remote consults divided by all
-- consults (add up first, then divide), never the average of the specialisms' shares, which
-- would give a tiny specialism the same weight as a huge one.
-- Read by Q1, Q3, Q4 and Q5.
-- Built from: v_specialism_year (so the clinic, remote and telemonitoring rules are not repeated).
-- Expected rows: 6 (one per year, 2019 to 2024). Cross-check: all consults over the six years =
-- 113,939,420 (check 2 of v_specialism_year).
CREATE VIEW v_national_year AS
SELECT year,
       SUM(clinic) AS clinic,                                            -- all clinic consults in the country
       SUM(remote) AS remote,                                            -- all remote consults in the country
       SUM(all_consults) AS all_consults,                                -- all consults in the country
       ROUND(100.0 * SUM(remote) / SUM(all_consults), 1) AS remote_share_pct   -- rule 3: add up first, then divide
FROM v_specialism_year                                                   -- the KPI rules are already applied there
GROUP BY year;                                                           -- one row per year

-- Check v_national_year 1: number of rows. Expected: 6
SELECT COUNT(*) AS row_count
FROM v_national_year;

-- Check v_national_year 2: total of all consults over the six years. Expected: 113,939,420
SELECT SUM(all_consults) AS total_consults
FROM v_national_year;

-- Check v_national_year 3 (why rule 3 matters): 2024, pooled share vs the average of the specialisms' shares.
-- Expected: the two numbers differ (the average gives small specialisms too much weight)
SELECT (SELECT remote_share_pct FROM v_national_year WHERE year = 2024) AS pooled_share,
       (SELECT ROUND(AVG(remote_share_pct), 1) FROM v_specialism_year WHERE year = 2024) AS average_of_shares;

-- v_specialism_growth: one row per specialism, with its 2019, 2022 and 2024 shares side by side.
-- Why it exists: KPI 3 (change 2024 minus 2019, momentum 2024 minus 2022) and the KPI 5 inputs
-- (clinic consults 2024) are calculated here once, so Q4, Q5 and Q8 to Q10 use the same numbers.
-- A pivot: MAX(CASE ...) picks each year's value from its own row. No ELSE 0, so a missing year
-- stays empty (sports medicine, 8416, has no 2019 row: its share_2019 and change_pts are empty).
-- Read by Q4, Q5, Q8, Q9 and Q10.
-- Built from: v_specialism_year.
-- Expected rows: 27 (one per specialism). Cross-check: clinic_2024 adds up to 12,677,043 and
-- all_2024 to 19,791,058 (the 2024 row of v_national_year).
CREATE VIEW v_specialism_growth AS
SELECT specialism_code,
       specialism_name,
       MAX(CASE WHEN year = 2024 THEN clinic END) AS clinic_2024,               -- KPI 5 headroom: follow-up visits still in the clinic
       MAX(CASE WHEN year = 2024 THEN all_consults END) AS all_2024,            -- KPI 1 size in 2024
       MAX(CASE WHEN year = 2019 THEN remote_share_pct END) AS share_2019,      -- pre-COVID baseline
       MAX(CASE WHEN year = 2022 THEN remote_share_pct END) AS share_2022,      -- start of the momentum window
       MAX(CASE WHEN year = 2024 THEN remote_share_pct END) AS share_2024,      -- last full year
       MAX(CASE WHEN year = 2024 THEN remote_share_pct END)
         - MAX(CASE WHEN year = 2019 THEN remote_share_pct END) AS change_pts,  -- KPI 3a, long-term change, in points
       MAX(CASE WHEN year = 2024 THEN remote_share_pct END)
         - MAX(CASE WHEN year = 2022 THEN remote_share_pct END) AS momentum_pts -- KPI 3b, recent momentum, in points
FROM v_specialism_year
WHERE year IN (2019, 2022, 2024)                                                -- only the three years the KPIs use
GROUP BY specialism_code, specialism_name;                                      -- one row per specialism

-- Check v_specialism_growth 1: number of rows. Expected: 27
SELECT COUNT(*) AS row_count
FROM v_specialism_growth;

-- Check v_specialism_growth 2: 2024 totals. Expected: clinic 12,677,043 and all 19,791,058 (v_national_year, 2024)
SELECT SUM(clinic_2024) AS clinic_2024,
       SUM(all_2024) AS all_2024
FROM v_specialism_growth;

-- Check v_specialism_growth 3: one row by hand. Ophthalmology (0301).
-- Expected: shares 3.4 (2019), 7.8 (2022), 8.9 (2024), change 5.5, momentum 1.1
SELECT share_2019, share_2022, share_2024, change_pts, momentum_pts
FROM v_specialism_growth
WHERE specialism_code = '0301';
