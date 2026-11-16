-- 01_schema.sql: creates the four empty tables of the remote_care database (run this first, then 02_load.sql)

-- Drop the views first: they depend on the tables (04_views.sql), so the tables cannot be dropped while they exist
DROP VIEW IF EXISTS v_specialism_growth;
DROP VIEW IF EXISTS v_national_year;
DROP VIEW IF EXISTS v_specialism_year;
DROP VIEW IF EXISTS v_base;

-- Drop first so the script can be re-run from scratch; the data is rebuilt from the CSVs by 02_load.sql
DROP TABLE IF EXISTS consult_volume; -- it points to specialism and activity
DROP TABLE IF EXISTS channel_map; -- it points to activity
DROP TABLE IF EXISTS activity;
DROP TABLE IF EXISTS specialism;

-- Lookup table: one row per specialism (from 06_REF_SPC.csv)
CREATE TABLE specialism (
    specialism_code TEXT PRIMARY KEY,    -- SPECIALISME_CD; text, not a number: codes like 0303 keep their leading zero
    specialism_name TEXT NOT NULL        -- OMSCHRIJVING; every specialism has a name
);

-- Lookup table: one row per care activity (from 03_REF_ZAT.csv)
CREATE TABLE activity (
    activity_code TEXT PRIMARY KEY,      -- ZORGACTIVITEIT_CD; text: 039133 (telemonitoring) keeps its leading zero
    activity_name TEXT NOT NULL,         -- OMSCHRIJVING
    class_code    TEXT NOT NULL,         -- ZORGPROFIELKLASSE_CD; activity group, e.g. 1 = outpatient and remote consults
    class_name    TEXT NOT NULL          -- ZORGPROFIELKLASSE_OMS
);

-- My mapping: which activity codes count as which channel (typed by hand, 6 rows, no source file)
CREATE TABLE channel_map (
    activity_code TEXT PRIMARY KEY REFERENCES activity (activity_code),  -- must be a real activity
    channel       TEXT NOT NULL,         -- clinic, phone, written, video or telemonitoring
    is_remote     BOOLEAN NOT NULL       -- true = counts in the remote share
);

-- Main table: number of activities per year, specialism and activity (summed from 02_DBC_PROFIEL.csv)
CREATE TABLE consult_volume (
    year            INTEGER NOT NULL,    -- JAAR (start year of the treatment path)
    specialism_code TEXT NOT NULL REFERENCES specialism (specialism_code),  -- BEHANDELEND_SPECIALISME_CD
    activity_code   TEXT NOT NULL REFERENCES activity (activity_code),      -- ZORGACTIVITEIT_CD
    activity_count  INTEGER NOT NULL,    -- sum of AANTAL_ZAT
    PRIMARY KEY (year, specialism_code, activity_code)  -- the three columns together are unique
);
