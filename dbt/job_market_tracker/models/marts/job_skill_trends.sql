WITH base AS 
(
SELECT 
	DATE(loaded_at) AS load_date,
    title,
    categories,
    company_name,
    seniority,
    employment_type,
    min_salary,
    max_salary,
    currency
FROM {{ ref('stg_job_tracker__raw_job_postings') }}
),

skill_flags AS
(
SELECT 
	load_date,
    seniority,
    employment_type,
    min_salary,
    max_salary,
    currency,
    CASE WHEN LOWER(title) LIKE '%sql%' 
        OR LOWER(categories) LIKE '%sql%' THEN 1 ELSE 0 END AS mentions_sql,
    CASE WHEN LOWER(title) LIKE '%python%' 
        OR LOWER(categories) LIKE '%python%' THEN 1 ELSE 0 END AS mentions_python,
    CASE WHEN LOWER(title) LIKE '%power bi%' 
        OR LOWER(title) LIKE '%powerbi%'
        OR LOWER(categories) LIKE '%power bi%' 
        OR LOWER(categories) LIKE '%powerbi%' THEN 1 ELSE 0 END AS mentions_power_bi,
    CASE WHEN LOWER(title) LIKE '%excel%' 
        OR LOWER(categories) LIKE '%excel%' THEN 1 ELSE 0 END AS mentions_excel,
    CASE WHEN LOWER(title) LIKE '%dbt%' 
        OR LOWER(categories) LIKE '%dbt%' THEN 1 ELSE 0 END AS mentions_dbt,
    CASE WHEN LOWER(title) LIKE '%looker%' 
        OR LOWER(categories) LIKE '%looker%' THEN 1 ELSE 0 END AS mentions_looker,
    CASE WHEN LOWER(title) LIKE '%n8n%' 
        OR LOWER(categories) LIKE '%n8n%' THEN 1 ELSE 0 END AS mentions_n8n
FROM base
),

aggregated AS
(
SELECT
	load_date,
    COUNT(*) AS total_postings,
    SUM(mentions_sql) AS sql_count,
    SUM(mentions_python) AS python_count,
    SUM(mentions_power_bi) AS power_bi_count,
    SUM(mentions_excel) AS excel_count,
    SUM(mentions_dbt) AS dbt_count,
    SUM(mentions_looker) AS looker_count,
    SUM(mentions_n8n) AS n8n_count
FROM skill_flags
GROUP BY load_date
)

SELECT * FROM aggregated
