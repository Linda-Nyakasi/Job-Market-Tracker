WITH stg_source AS 
(
SELECT *
FROM {{ source('job_market_tracker', 'raw_job_postings') }}
),

staged AS
(
SELECT
    guid,
    title,
    company_name,
    company_slug,
    employment_type,
    min_salary,
    max_salary,
    currency,
    seniority,
    categories,
    location_restrictions,
    FROM_UNIXTIME (pub_date) AS pub_date,
    loaded_at
FROM stg_source
WHERE guid IS NOT NULL
AND title IS NOT NULL
)

SELECT *
FROM staged
