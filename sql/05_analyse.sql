-- 05_analyse.sql: the ten answer queries, one business question each, all reading from the views
-- Run after 04_views.sql (psql -d remote_care -f sql/05_analyse.sql)

-- Q1: how did the national remote share move from 2019 to 2024, and did it stay up after 2020?
-- KPI / hypothesis: KPI 2 benchmark, H2 (remote care stayed up after the 2020 jump)
-- Reads: v_national_year
-- Expected rows: 6 (one per year, 2019 to 2024)
-- Prediction: none written before running (ran straight away)
SELECT year,
       all_consults,                                                     -- all follow-up consults in the country
       remote,                                                           -- of which remote (phone, video, written)
       remote_share_pct,                                                 -- remote / all, in %
       remote_share_pct - LAG(remote_share_pct) OVER (ORDER BY year)
           AS change_pts                                                 -- change from the year before, in percentage points (empty for 2019)
FROM v_national_year
ORDER BY year;                                                           -- oldest year first, so the trend reads top to bottom
-- Result: during COVID the remote share jumped from 15.5% (2019) to 43.0% (2020), then decreased
-- to 34.4% by 2023, and is increasing again in 2024 (35.9%). It stayed 20.4 points above 2019,
-- so H2 is supported: remote care fell back after the peak but did not return to the pre-COVID level.

-- Q2: how big is each specialism in 2024, and what share of all Dutch follow-up consults does it have?
-- KPI / hypothesis: KPI 1 (volume), sub-question 1 (Size)
-- Reads: v_specialism_year
-- Expected rows: 27 (one per specialism in 2024). Cross-check: pct_of_national adds up to about 100,
-- and the total behind it is 19,791,058 (Q1, 2024)
-- Prediction: none written before running
SELECT specialism_code,
       specialism_name,
       all_consults,                                                          -- follow-up consults in 2024 (clinic + remote)
       ROUND(100.0 * all_consults / SUM(all_consults) OVER (), 1)
           AS pct_of_national                                                 -- share of all consults in the country; OVER () = total over all 27 rows
FROM v_specialism_year
WHERE year = 2024                                                             -- runs before OVER (), so the total is the 2024 national total
ORDER BY all_consults DESC;                                                   -- biggest specialism first
-- Result: internal medicine is the biggest specialism (2,855,518 consults, 14.4% of the national
-- total), followed by surgery (10.0%). The 14 specialisms with at least 3.4% each hold 93.7% of all
-- follow-up consults; the other 13 are each under 2%, and psychiatry, radiology and audiology are
-- below 0.1%. For the product team: realistic targets come from those 14, the rest is too small a market.

-- Q3: how remote is each specialism in 2019 and 2024, compared with the national share?
-- KPI / hypothesis: KPI 2 (remote share), sub-question 2 (Adoption)
-- Reads: v_specialism_year (shares per specialism), v_national_year (national benchmark)
-- Expected rows: 27 (one per specialism). Sports medicine (8416) has no 2019 row, so its share_2019 is empty.
-- Prediction: none written before running
SELECT specialism_code,
       specialism_name,
       MAX(CASE WHEN year = 2019 THEN remote_share_pct END) AS share_2019,           -- pivot: picks the 2019 row's share (empty if there is no 2019 row)
       MAX(CASE WHEN year = 2024 THEN remote_share_pct END) AS share_2024,           -- pivot: picks the 2024 row's share
       (SELECT remote_share_pct FROM v_national_year WHERE year = 2019) AS national_2019,   -- benchmark, the same on every row
       (SELECT remote_share_pct FROM v_national_year WHERE year = 2024) AS national_2024,   -- benchmark, the same on every row
       MAX(CASE WHEN year = 2024 THEN remote_share_pct END)
         - (SELECT remote_share_pct FROM v_national_year WHERE year = 2024) AS gap_pts      -- above (+) or below (-) the country in 2024, in points
FROM v_specialism_year
WHERE year IN (2019, 2024)                                                           -- only the two years compared
GROUP BY specialism_code, specialism_name                                            -- one row per specialism
ORDER BY share_2024 DESC, specialism_name;                                           -- most remote first; name breaks ties (49.7% twice), so the order never changes
-- Result: every specialism is more remote in 2024 than in 2019, and 15 of 27 are above the national
-- share (35.9%). The highest shares are in small specialisms (clinical genetics 85.9%, radiology 81.0%,
-- anaesthesiology 68.8%), each under 2% of all consults (Q2). Among the 14 large specialisms,
-- gastroenterology leads (62.9%), then neurology and paediatrics (49.7%) and internal medicine (44.9%).
-- The large hands-on specialisms are furthest below the country: surgery 30.6%, orthopaedics 27.4%,
-- dermatology 23.9%, ENT 20.5% and ophthalmology 8.9%, the lowest of all.
-- Meaning: H2 holds per specialism, not only nationally. A first sign for H3: the highest shares
-- are in specialisms too small to be targets, so ranking by share alone would point the product
-- team at the wrong specialisms. Q8 tests this properly with size and growth together.

-- Q4: how much did each specialism's remote share grow since 2019, and is it still growing since 2022?
-- KPI / hypothesis: KPI 3a (change 2024 minus 2019) and KPI 3b (momentum 2024 minus 2022), H2 and H3
-- Reads: v_specialism_growth, v_national_year (national benchmark, in a CTE)
-- Expected rows: 27. Sports medicine (8416) has no 2019 share, so its change_pts is empty.
-- Prediction: none written before running
WITH national AS (                                                         -- CTE: the national change and momentum, calculated once
    SELECT MAX(CASE WHEN year = 2024 THEN remote_share_pct END)
             - MAX(CASE WHEN year = 2019 THEN remote_share_pct END) AS national_change_pts,
           MAX(CASE WHEN year = 2024 THEN remote_share_pct END)
             - MAX(CASE WHEN year = 2022 THEN remote_share_pct END) AS national_momentum_pts
    FROM v_national_year
)
SELECT g.specialism_code,
       g.specialism_name,
       g.share_2019,
       g.share_2022,
       g.share_2024,
       g.change_pts,                                                       -- KPI 3a: points gained since 2019
       n.national_change_pts,                                              -- the same for the whole country
       g.momentum_pts,                                                     -- KPI 3b: points gained since 2022 (0 or below = stopped or falling)
       n.national_momentum_pts                                             -- the same for the whole country
FROM v_specialism_growth AS g
CROSS JOIN national AS n                                                   -- national has one row, so it is added to every specialism
ORDER BY g.momentum_pts DESC, g.specialism_name;                             -- still growing fastest first; name breaks ties (+1.8 twice), so the order never changes
-- Result: every specialism with 2019 data gained since 2019 (+5.5 points for ophthalmology up to
-- +37.1 for allergology; country +20.4). Momentum since 2022 is small everywhere (country +1.2):
-- the largest gains are in small specialisms (radiology +8.1, allergology +7.7), and among the large
-- ones in gynaecology (+5.4), paediatrics (+4.9) and dermatology (+3.5). Five specialisms fell back
-- since 2022, four of them large and already highly remote: cardiology (-2.0), gastroenterology (-1.7),
-- pulmonology (-1.4) and rheumatology (-0.2), plus neurosurgery (-0.6); neurology is flat (0.0).
-- Meaning: the growth now comes from specialisms with a medium share, while several of the most remote
-- large ones have levelled off, which is what H3 expects.

-- Q5: how many specialisms stayed above their 2019 share, and how many fell back since 2022?
-- KPI / hypothesis: KPI 3a and 3b, H2 (remote care stayed up after the 2020 jump, in most specialisms)
-- Reads: v_specialism_growth
-- Expected rows: 1 (a summary). Cross-check: 26 specialisms have a 2019 share (27 minus sports medicine).
-- Prediction: none written before running
SELECT COUNT(*) AS specialisms,                                                   -- all 27
       COUNT(share_2019) AS with_2019_data,                                       -- COUNT(column) skips empty values: 26
       COUNT(CASE WHEN change_pts > 0 THEN 1 END) AS above_2019,                  -- KPI 3a above 0
       COUNT(CASE WHEN momentum_pts > 0 THEN 1 END) AS still_growing_since_2022,  -- KPI 3b above 0
       COUNT(CASE WHEN momentum_pts = 0 THEN 1 END) AS flat_since_2022,
       COUNT(CASE WHEN momentum_pts < 0 THEN 1 END) AS fell_back_since_2022       -- KPI 3b below 0
FROM v_specialism_growth;
-- Result: all 26 specialisms with 2019 data are above their 2019 share in 2024. Since 2022, 21 of 27
-- are still growing, 1 is flat and 5 fell back slightly (at most -2.0 points, Q4).
-- Meaning: H2 is supported in every specialism, not only nationally. Remote care is a lasting part of
-- follow-up care, not a COVID effect that faded.

-- Q6: which forms make up remote care, and how did the mix change from 2019 to 2024?
-- KPI / hypothesis: KPI 4 (channel mix), Belief 1 (video is the main and fastest-growing form)
-- Reads: v_base (the metric views have already merged the channels into one remote number)
-- Expected rows: 3 (phone, written, video). Cross-check: the counts add up to the national remote
-- total, 2,912,088 in 2019 and 7,114,015 in 2024 (Q1).
-- Prediction: none written before running
WITH channel_years AS (                                                    -- CTE: one row per channel, the two years side by side
    SELECT channel,
           SUM(CASE WHEN year = 2019 THEN activity_count ELSE 0 END) AS count_2019,
           SUM(CASE WHEN year = 2024 THEN activity_count ELSE 0 END) AS count_2024
    FROM v_base
    WHERE is_remote                                                        -- phone, video and written only
      AND year IN (2019, 2024)
    GROUP BY channel
)
SELECT channel,
       count_2019,
       ROUND(100.0 * count_2019 / SUM(count_2019) OVER (), 1) AS pct_of_remote_2019,   -- share of all remote consults
       count_2024,
       ROUND(100.0 * count_2024 / SUM(count_2024) OVER (), 1) AS pct_of_remote_2024,
       count_2024 - count_2019 AS added,                                               -- real numbers next to the % growth
       ROUND(100.0 * (count_2024 - count_2019) / count_2019, 1) AS growth_pct          -- KPI 4: % growth, read together with added
FROM channel_years
ORDER BY count_2024 DESC;                                                  -- largest channel first
-- Result: phone is almost all of remote care: 99.1% in 2019 and 98.0% in 2024 (6,968,847 consults,
-- 4.1 million more than in 2019). Video grew fastest in percent (+889.7%), but from 6,517 to only
-- 64,502, which is 0.9% of remote consults; written care is 1.1%.
-- Meaning: Belief 1 is wrong. Video is the fastest-growing form only in percent, and it is not the
-- main form at all. For the product team: Dutch remote follow-up care is a phone market; a video
-- product competes with the phone, not with an existing video habit.

-- Q7: how much telemonitoring is there, and is it growing?
-- KPI / hypothesis: KPI 4, rule 4 (telemonitoring is counted on its own, not in the remote share)
-- Reads: v_base
-- Expected rows: 6 (one per year). Cross-check: the six years add up to 586,144 (v_specialism_year header).
-- Prediction: none written before running
SELECT year,
       SUM(activity_count) AS telemonitoring,                              -- telemonitoring activities in the year
       COUNT(*) AS specialisms_using                                       -- v_base has one row per specialism that used it
FROM v_base
WHERE channel = 'telemonitoring'
GROUP BY year
ORDER BY year;
-- Result: telemonitoring roughly doubled, from 62,581 (2019) to 123,830 (2024), with a dip in 2022
-- (90,475), and it is used by 21 specialisms in 2024 (18 in 2019). It is small next to the 7.1 million
-- remote consults.
-- Meaning: a growing but small, separate market; not part of the target ranking.

-- Q8: where is the biggest opportunity? Clinic follow-up consults in 2024, for specialisms where remote
-- care is proven (share at least 10%) and still growing (momentum above 0), largest first.
-- KPI / hypothesis: KPI 5 (headroom), the main question; top 3 = the targets
-- Reads: v_specialism_growth
-- Expected rows: 20 (27 minus ophthalmology, below 10%, minus the 6 with momentum 0 or below, Q5).
-- Prediction: none written before running
WITH eligible AS (                                                         -- CTE: step 1, keep only the specialisms that pass both filters
    SELECT specialism_code,
           specialism_name,
           clinic_2024,
           share_2024,
           momentum_pts
    FROM v_specialism_growth
    WHERE share_2024 >= 10                                                 -- remote care proven (floor fixed before any query)
      AND momentum_pts > 0                                                 -- still growing since 2022
)
SELECT RANK() OVER (ORDER BY clinic_2024 DESC) AS headroom_rank,           -- step 2, rank by headroom; ties would share a rank
       specialism_code,
       specialism_name,
       clinic_2024 AS headroom,                                            -- follow-up visits that could still move to remote
       share_2024,
       momentum_pts
FROM eligible
ORDER BY headroom_rank;
-- Result: the top 3 are internal medicine (1,573,274 clinic follow-ups, share 44.9%, momentum +0.3),
-- surgery (1,369,124; 30.6%; +1.8) and dermatology (1,095,282; 23.9%; +3.5), followed closely by
-- gynaecology (1,041,215; 29.3%; +5.4). Excluded: ophthalmology (largest clinic volume of all
-- excluded, but 8.9% remote) and cardiology, gastroenterology, pulmonology, rheumatology, neurology
-- and neurosurgery (no momentum).
-- Meaning: the answer to the main question. Target internal medicine, surgery and dermatology in 2027.
-- Watch: internal medicine's momentum (+0.3) is barely above 0, so it is the least secure of the three;
-- gynaecology is the natural fourth.

-- Q9: hypothesis test (H3). Are the specialisms with the highest remote share the same as the best targets?
-- KPI / hypothesis: H3 (the best targets are large specialisms with a medium share still growing,
-- not the ones with the highest share)
-- Reads: v_specialism_growth
-- Expected rows: 3 (rank 1 to 3 side by side)
-- Prediction: none written before running
WITH by_share AS (                                                         -- CTE 1: all specialisms ranked by 2024 share
    SELECT ROW_NUMBER() OVER (ORDER BY share_2024 DESC) AS rank_no,
           specialism_name,
           share_2024,
           all_2024
    FROM v_specialism_growth
),
by_headroom AS (                                                           -- CTE 2: the Q8 ranking (same two filters)
    SELECT ROW_NUMBER() OVER (ORDER BY clinic_2024 DESC) AS rank_no,
           specialism_name,
           share_2024,
           clinic_2024
    FROM v_specialism_growth
    WHERE share_2024 >= 10
      AND momentum_pts > 0
)
SELECT s.rank_no,
       s.specialism_name AS top_by_share,
       s.share_2024 AS share_pct,
       s.all_2024 AS consults,                                             -- size of the high-share specialism
       h.specialism_name AS top_by_headroom,
       h.share_2024 AS headroom_share_pct,
       h.clinic_2024 AS headroom
FROM by_share AS s
JOIN by_headroom AS h ON s.rank_no = h.rank_no                             -- rank 1 next to rank 1, and so on
WHERE s.rank_no <= 3
ORDER BY s.rank_no;
-- Result: the top 3 by share are clinical genetics (85.9%), radiology (81.0%) and anaesthesiology
-- (68.8%), with 42,110, 1,676 and 268,314 consults. The top 3 by headroom are internal medicine, surgery
-- and dermatology, with medium shares (44.9%, 30.6%, 23.9%). No specialism is on both lists.
-- Meaning: H3 is supported. The highest shares are in small specialisms with little left to move; the
-- opportunity is in large specialisms with a medium share that is still growing.

-- Q10: sensitivity check. Does the top 3 change if the floor is 5% or 15% instead of 10%?
-- KPI / hypothesis: KPI 5; the 10% floor is the one judgment call, so this shows whether the answer depends on it
-- Reads: v_specialism_growth
-- Expected rows: 9 (top 3 for each of the three floors)
-- Prediction: none written before running
WITH floors AS (                                                           -- CTE 1: the three floors to test, typed in as a small table
    SELECT floor_pct
    FROM (VALUES (5), (10), (15)) AS f (floor_pct)
),
ranked AS (                                                                -- CTE 2: the Q8 ranking, once per floor
    SELECT f.floor_pct,
           g.specialism_name,
           g.clinic_2024,
           g.share_2024,
           RANK() OVER (PARTITION BY f.floor_pct ORDER BY g.clinic_2024 DESC) AS headroom_rank  -- PARTITION BY: rank again from 1 for each floor
    FROM floors AS f
    CROSS JOIN v_specialism_growth AS g                                    -- every floor paired with every specialism
    WHERE g.share_2024 >= f.floor_pct
      AND g.momentum_pts > 0
)
SELECT floor_pct,
       headroom_rank,
       specialism_name,
       clinic_2024 AS headroom,
       share_2024
FROM ranked
WHERE headroom_rank <= 3                                                   -- a window result can only be filtered after the CTE, not in its own WHERE
ORDER BY floor_pct, headroom_rank;
-- Result: at 10% and 15% the top 3 is the same (internal medicine, surgery, dermatology). At 5%,
-- ophthalmology (8.9% remote, momentum +1.1) enters at rank 3 with 1,252,628 clinic follow-ups and
-- pushes dermatology out.
-- Meaning: the answer holds for any floor from 10% upward, and depends on the floor only below 8.9%.
-- Ophthalmology is a large market where remote care is still unproven: a possible later bet, not a 2027 target.
