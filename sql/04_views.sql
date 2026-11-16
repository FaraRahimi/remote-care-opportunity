-- 04_views.sql: creates the three views used by the analysis (run after 03_validate.sql)
-- Layers: tables -> v_base (rules) -> v_specialism_year (KPIs per specialism) -> v_national_year (KPIs for the country)

-- Drop the views first so the file can be re-run from the top
-- (CREATE VIEW fails if the view already exists). Reverse order: last built, first dropped.
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
