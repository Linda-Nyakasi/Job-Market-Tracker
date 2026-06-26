# dbt Project: job_market_tracker

## Models
- staging/stg_job_postings: cleans raw postings, converts pub_date from Unix timestamp
- marts/job_skill_trends: daily skill keyword frequency
- marts/job_seniority_salary: salary statistics by seniority and employment type

## Running
dbt debug  
dbt run  
dbt test  

## Profiles
profiles.yml lives at ~/.dbt/profiles.yml (not committed to repo for security)  
See main README for connection configuration.
