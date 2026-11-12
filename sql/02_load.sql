-- 02_load.sql: loads the CSVs from data/raw/ into staging tables, then fills the four final tables (run after 01_schema.sql)

-- Staging table for 06_REF_SPC.csv: exact copy of the CSV, every column text, no rules
DROP TABLE IF EXISTS stg_specialism;
CREATE TABLE stg_specialism (
    versie         TEXT,
    datum_bestand  TEXT,
    peildatum      TEXT,
    specialisme_cd TEXT,
    omschrijving   TEXT
);

-- Staging table for 03_REF_ZAT.csv: exact copy of the CSV, every column text, no rules
DROP TABLE IF EXISTS stg_activity;
CREATE TABLE stg_activity (
    versie                TEXT,
    datum_bestand         TEXT,
    peildatum             TEXT,
    zorgactiviteit_cd     TEXT,
    omschrijving          TEXT,
    zorgprofielklasse_cd  TEXT,
    zorgprofielklasse_oms TEXT
);

-- Staging table for 02_DBC_PROFIEL.csv: exact copy of the CSV, every column text, no rules
DROP TABLE IF EXISTS stg_profile;
CREATE TABLE stg_profile (
    versie                     TEXT,
    datum_bestand              TEXT,
    peildatum                  TEXT,
    jaar                       TEXT,
    behandelend_specialisme_cd TEXT,
    typerende_diagnose_cd      TEXT,
    zorgproduct_cd             TEXT,
    zorgactiviteit_cd          TEXT,
    zorgprofielklasse_cd       TEXT,
    aantal_pat                 TEXT,
    aantal_subtraject          TEXT,
    aantal_zat                 TEXT,
    som_aantal_zat             TEXT
);

-- Load each CSV into its staging table (\copy is a psql command: one line, no semicolon)
-- HEADER true skips the first line of the file, which holds the column names
\copy stg_specialism FROM 'data/raw/06_REF_SPC.csv' WITH (FORMAT csv, HEADER true)

-- Activity reference: 4,074 rows
\copy stg_activity FROM 'data/raw/03_REF_ZAT.csv' WITH (FORMAT csv, HEADER true)

-- The big file: 10,865,746 rows, takes a minute or two
\copy stg_profile FROM 'data/raw/02_DBC_PROFIEL.csv' WITH (FORMAT csv, HEADER true)

-- Check: staging row counts must be 701, 4,074 and 10,865,746
SELECT COUNT(*) FROM stg_specialism;
SELECT COUNT(*) FROM stg_activity;
SELECT COUNT(*) FROM stg_profile;

-- Fill the specialism table from staging (701 rows)
INSERT INTO specialism (specialism_code, specialism_name)
SELECT specialisme_cd, omschrijving
FROM stg_specialism;

-- Fill the activity table from staging (4,074 rows)
INSERT INTO activity (activity_code, activity_name, class_code, class_name)
SELECT zorgactiviteit_cd, omschrijving, zorgprofielklasse_cd, zorgprofielklasse_oms
FROM stg_activity;

-- Fill the channel_map table: my mapping, typed by hand (6 rows)
INSERT INTO channel_map (activity_code, channel, is_remote) VALUES
    ('190013', 'clinic',         FALSE),   -- follow-up clinic visit
    ('190162', 'phone',          TRUE),    -- phone consult replacing a follow-up visit
    ('190163', 'written',        TRUE),    -- written consult replacing a follow-up visit
    ('190161', 'video',          TRUE),    -- video consult, 2018 to 2020 (no first/follow-up split)
    ('190166', 'video',          TRUE),    -- video consult replacing a follow-up visit, from 2021
    ('039133', 'telemonitoring', FALSE);   -- reported separately, not in the remote share

-- How many staging rows will be dropped because their activity code is missing from activity
SELECT COUNT(*) AS rows_dropped, COUNT(DISTINCT zorgactiviteit_cd) AS codes_missing
FROM stg_profile
WHERE zorgactiviteit_cd NOT IN (SELECT activity_code FROM activity);

-- Fill the main table: convert text to numbers, keep only known activity codes,
-- and sum the 10.8 million rows to one row per year, specialism and activity
INSERT INTO consult_volume (year, specialism_code, activity_code, activity_count)
SELECT
    jaar::INTEGER,
    behandelend_specialisme_cd,
    zorgactiviteit_cd,
    SUM(aantal_zat::INTEGER)
FROM stg_profile
WHERE zorgactiviteit_cd IN (SELECT activity_code FROM activity)
GROUP BY jaar, behandelend_specialisme_cd, zorgactiviteit_cd;
