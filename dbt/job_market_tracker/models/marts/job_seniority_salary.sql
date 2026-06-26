WITH base AS (
    SELECT
        date(loaded_at)  as load_date,
        seniority,
        employment_type,
        currency,
        min_salary,
        max_salary
    FROM {{ ref('stg_job_tracker__raw_job_postings') }}
    WHERE seniority IS NOT NULL
      AND seniority != ''
),

aggregated AS (
    SELECT
        load_date,
        seniority,
        employment_type,
        currency,
        count(*) as total_postings,
        round(avg(min_salary), 0) as avg_min_salary,
        round(avg(max_salary), 0) as avg_max_salary,
        min(min_salary) as lowest_min_salary,
        max(max_salary) as highest_max_salary
    FROM base
    GROUP BY
        load_date,
        seniority,
        employment_type,
        currency
)

SELECT * FROM aggregated
