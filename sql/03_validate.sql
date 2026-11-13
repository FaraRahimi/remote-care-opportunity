-- 03_validate.sql: checks that the load is correct, each with its expected number (run after 02_load.sql)

-- Check 1: row counts of the four tables. Expected: specialism 701, activity 4,074, channel_map 6, consult_volume 185,440
SELECT COUNT(*) FROM specialism;
SELECT COUNT(*) FROM activity;
SELECT COUNT(*) FROM channel_map;
SELECT COUNT(*) FROM consult_volume;

-- Check 2: grand total of all activities. Expected: 1,186,779,701 (the load checksum)
SELECT SUM(activity_count) FROM consult_volume;

-- Check 3: rows and total activities per year. Expected: 15 lines (2012 to 2026), 2026 much smaller (still being filled in)
SELECT
    year,                                       -- one result line per year
    COUNT(*) AS row_count,                      -- how many rows that year has
    SUM(activity_count) AS total_activities     -- all activities that year added up
FROM consult_volume
GROUP BY year                                   -- split the table into one group per year
ORDER BY year;                                  -- show the years in order, 2012 first

-- Check 4: number of different specialisms in consult_volume. Expected: 28 (Part B), out of 701 in the specialism table
SELECT COUNT(DISTINCT specialism_code) FROM consult_volume;

-- Check 5a: the 6 mapped codes with their real names. Expected: 6 lines, consult codes in class 1, telemonitoring in class 4
SELECT channel_map.activity_code, channel_map.channel, activity.activity_name, activity.class_code
FROM channel_map
JOIN activity ON channel_map.activity_code = activity.activity_code   -- match each mapped code to its own row in activity
ORDER BY channel_map.channel;                                          -- the two video codes sit next to each other

-- Check 5b: first and last year of each mapped code. Expected: video 190161 2018-2020, video 190166 2021-2026
SELECT activity_code, MIN(year) AS first_year, MAX(year) AS last_year
FROM consult_volume
WHERE activity_code IN (SELECT activity_code FROM channel_map)   -- only my 6 mapped codes
GROUP BY activity_code                                            -- one line per code
ORDER BY activity_code;

-- Check 6: fan-out check, 2019-2024 total of the 6 mapped codes, without and with the join. Expected: both totals equal
SELECT SUM(activity_count) AS without_join
FROM consult_volume
WHERE activity_code IN (SELECT activity_code FROM channel_map)
  AND year BETWEEN 2019 AND 2024;

SELECT SUM(consult_volume.activity_count) AS with_join
FROM consult_volume
JOIN channel_map ON consult_volume.activity_code = channel_map.activity_code
WHERE year BETWEEN 2019 AND 2024;

-- Check 7: spot-check one cell, 2024, ophthalmology (0301), phone (190162). Expected: both numbers equal (118,888)
SELECT SUM(aantal_zat::INTEGER) AS in_staging          -- staging stores text, so convert to a number before adding
FROM stg_profile
WHERE jaar = '2024'                                    -- text column, so the year is in quotes
  AND behandelend_specialisme_cd = '0301'              -- ophthalmology (oogheelkunde)
  AND zorgactiviteit_cd = '190162';                    -- phone consult replacing a follow-up visit

SELECT activity_count AS in_final                      -- the same cell after loading and summing
FROM consult_volume
WHERE year = 2024                                      -- INTEGER column, so no quotes
  AND specialism_code = '0301'                         -- codes are TEXT, so quotes (keeps the leading zero)
  AND activity_code = '190162';
