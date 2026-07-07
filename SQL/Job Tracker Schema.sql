-- ============================================================
-- Job Market Tracker: SQL Reference
-- ============================================================
-- This file documents the database setup and key verification
-- queries used during development. Mart model SQL lives inside
-- dbt (models/marts/). Refer there for transformation logic.
-- ============================================================


-- ============================================================
-- 1. DATABASE AND TABLE SETUP
-- ============================================================

CREATE DATABASE IF NOT EXISTS job_market_tracker;
USE job_market_tracker;

CREATE TABLE raw_job_postings (
    id                    INT AUTO_INCREMENT PRIMARY KEY,
    guid                  VARCHAR(255) UNIQUE NOT NULL,
    title                 VARCHAR(500),
    company_name          VARCHAR(255),
    company_slug          VARCHAR(255),
    employment_type       VARCHAR(100),
    min_salary            INT,
    max_salary            INT,
    currency              VARCHAR(10),
    seniority             VARCHAR(100),
    categories            TEXT,
    location_restrictions TEXT,
    pub_date              VARCHAR(100),
    loaded_at             TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

/*
Design notes:
- guid UNIQUE NOT NULL: enforces deduplication at the database level.
  MySQL rejects a second insert of the same job; the n8n upsert node
  updates the existing row instead.
- pub_date VARCHAR(100): stored as raw text because the Himalayas API
  returns it as a Unix timestamp string. Conversion to datetime is
  handled downstream in the dbt staging model using FROM_UNIXTIME().
- loaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP: tracks when each row
  entered the database, separate from pub_date (when the job was posted).
  Used to partition daily snapshots in dbt mart models.
- AUTO_INCREMENT ID gaps are expected and normal: MySQL advances the
  counter on every insert attempt, including those converted to updates
  by the upsert logic. If you want clean sequential IDs, drop and
  recreate the table. The data itself is unaffected by the gaps.
*/


-- ============================================================
-- 2. RAW TABLE VERIFICATION
-- ============================================================

-- Confirm table exists and structure is correct
DESCRIBE raw_job_postings;

-- Check row count (expected: grows daily as n8n pipeline runs)
SELECT COUNT(*) FROM job_market_tracker.raw_job_postings;

-- Check for broken rows (should return empty result set)
SELECT * FROM job_market_tracker.raw_job_postings
WHERE title IS NULL OR guid IS NULL;

-- Inspect full raw data
SELECT * FROM job_market_tracker.raw_job_postings;


-- ============================================================
-- 3. STAGING MODEL VERIFICATION
-- ============================================================

/*
The staging model stg_job_tracker__raw_job_postings is materialised
as a VIEW in dbt. It:
- Excludes the surrogate id column (no business meaning, gaps from upserts)
- Filters out rows where guid or title is NULL
- Converts pub_date from Unix timestamp to datetime using FROM_UNIXTIME()

guid is used as the trace key: it is the full Himalayas job URL,
globally unique and stable across pipeline runs.
*/

-- Confirm the staging view exists
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'job_market_tracker'
  AND table_type = 'VIEW';

-- Inspect staging model output
SELECT * FROM job_market_tracker.stg_job_tracker__raw_job_postings;

-- Confirm row count matches expectations
SELECT COUNT(*) FROM job_market_tracker.stg_job_tracker__raw_job_postings;


-- ============================================================
-- 4. MART MODEL VERIFICATION
-- ============================================================

/*
Mart models are materialised as TABLEs in dbt and built automatically
when dbt run or dbt build is executed. The SQL logic lives in:
  models/marts/job_skill_trends.sql
  models/marts/job_seniority_salary.sql

Recommended development workflow:
1. Write and validate SQL directly in MySQL Workbench against raw tables.
2. Once confirmed correct, paste into the dbt model file and replace
   raw table references with {{ source() }} or {{ ref() }} references.
3. Add tests and documentation in the YAML files.
4. Run dbt build to materialise and test in one step.
*/

-- Inspect skill trends mart
SELECT * FROM job_market_tracker.job_skill_trends;

-- Inspect seniority salary mart
SELECT * FROM job_market_tracker.job_seniority_salary;


-- ============================================================
-- 5. AD HOC INVESTIGATION QUERIES
-- ============================================================

-- Check Power BI skill detection: verify which postings mention
-- Power BI (catching both spaced and unspaced variants)
SELECT *
FROM raw_job_postings
WHERE LOWER(title) LIKE '%power bi%'
   OR LOWER(title) LIKE '%powerbi%'
   OR LOWER(categories) LIKE '%power bi%'
   OR LOWER(categories) LIKE '%powerbi%';

-- Check SQL skill mentions
SELECT *
FROM raw_job_postings
WHERE LOWER(title) LIKE '%sql%'
   OR LOWER(categories) LIKE '%sql%';