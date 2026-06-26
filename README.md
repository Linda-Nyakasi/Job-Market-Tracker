# Data Analyst Job Market Tracker

An automated ELT pipeline that tracks remote data analyst job postings daily, transforms the raw data using dbt, and visualises trends in a two-page Power BI report. Built to demonstrate end-to-end data engineering skills: API ingestion, workflow automation, SQL modelling, and business intelligence reporting.

---

## Table of Contents

- [Project Overview](#project-overview)
- [Architecture](#architecture)
- [Tech Stack](#tech-stack)
- [Pipeline Walkthrough](#pipeline-walkthrough)
- [dbt Models](#dbt-models)
- [Power BI Report](#power-bi-report)
- [Database Schema](#database-schema)
- [Design Decisions](#design-decisions)
- [Known Limitations](#known-limitations)
- [Future Improvements](#future-improvements)
- [How to Run Locally](#how-to-run-locally)

---

## Project Overview

This project answers the question: **what does the remote data analyst job market look like, and how is it changing over time?**

The pipeline pulls job postings daily from the [Himalayas.app API](https://himalayas.app/jobs/api), a remote job board with a public, documented API, loads them into a MySQL database, transforms the raw data using dbt, and surfaces insights in a two-page Power BI report covering market demand and compensation analysis.

The project is designed to grow more meaningful over time: with one day of data it shows a snapshot; with weeks of data it shows real trends.

---

## Architecture

```
Himalayas.app API
        |
        v
   n8n (self-hosted via Docker)
   - Schedule Trigger (daily)
   - HTTP Request node
   - Split Out node
   - Edit Fields node
   - MySQL: Insert or Update (upsert)
        |
        v
   MySQL: raw_job_postings
        |
        v
   dbt (local)
   - stg_job_tracker__raw_job_postings (view)
   - job_seniority_salary (table)
   - job_skill_trends (table)
        |
        v
   Power BI Report
   - Page 1: Data Analyst Market Demand & Job Landscapes
   - Page 2: Compensation Deep Dive: Salary (USD) & Seniority
```

**Pattern:** ELT (Extract, Load, Transform).   
Data is landed raw and unchanged into MySQL first, then transformed by dbt into analytics-ready models. This separates concerns cleanly: n8n owns ingestion, dbt owns transformation logic.

---

## Tech Stack

| Layer | Tool |
|---|---|
| Workflow automation | n8n (self-hosted, Docker) |
| Data source | Himalayas.app Public API |
| Storage | MySQL (local) |
| Transformation | dbt-core 1.7.9 with dbt-mysql adapter |
| Visualisation | Power BI Desktop |
| Development environment | VS Code, MySQL Workbench |
| Version control | Git / GitHub |

---

## Pipeline Walkthrough

### Extract
The n8n HTTP Request node calls the Himalayas API search endpoint daily:

```
GET https://himalayas.app/jobs/api/search
Query parameter: q = data analyst
```

The API returns up to 20 job postings per request in JSON format, each containing title, company, seniority, employment type, salary range, categories, location restrictions, and a publication date as a Unix timestamp.

Per the Himalayas API documentation, data refreshes every 24 hours, so there is no benefit to polling more frequently than once per day.

### Load
The raw JSON response is processed in n8n before landing in MySQL:

- A **Split Out** node unpacks the `jobs` array into individual rows (one per job posting)
- An **Edit Fields** node selects only the columns needed for analysis and renames them to snake_case to match the MySQL table schema
- A **MySQL upsert node** (Insert or Update) writes each row to `raw_job_postings`, matching on `guid` (the unique job URL) to prevent duplicates across daily runs

The `categories` and `location_restrictions` fields are stored as comma-separated text strings since MySQL does not support a native array type. Each was originally an array in the API response and was joined using n8n's `.join(', ')` expression before loading.

### Transform
dbt reads from `raw_job_postings` and produces three models. See [dbt Models](#dbt-models) below.

---

## dbt Models

### Staging Layer

**[stg_job_tracker__raw_job_postings](dbt/job_market_tracker/models/staging/stg_job_tracker__raw_job_postings.sql)** (view)

A clean, lightly transformed representation of the raw source data. Selects all columns except the surrogate `id` (a database-generated row counter with no business meaning), filters out rows where `guid` or `title` is null, and converts `pub_date` from a Unix timestamp to a proper MySQL datetime using `FROM_UNIXTIME()`.

The Unix timestamp conversion is handled at the dbt layer rather than in n8n or Power Query, keeping transformation logic centralised and ensuring any downstream tool connecting to this view receives a correctly typed date column automatically.

```sql
FROM_UNIXTIME(pub_date) as pub_date
```

`guid` is the natural, meaningful identifier for each job posting (the full Himalayas URL, globally unique and stable across pipeline runs), and is used as the trace key in place of the surrogate `id`.

**Source definition:** [job_tracker__sources](dbt/job_market_tracker/models/staging/job_tracker__sources.yml) registers `raw_job_postings` as a dbt source, enabling `{{ source() }}` references throughout the project and making the pipeline portable: switching databases later requires updating only the source definition, not every model.

### Mart Layer

**[job_seniority_salary](dbt/job_market_tracker/models/marts/job_seniority_salary.sql)** (table)

Aggregates posting counts and salary statistics (average min, average max, lowest min, highest max) grouped by `load_date`, `seniority`, `employment_type`, and `currency`. Retained as a backend analytics asset for potential future use in SQL queries or additional tooling connections.

**[job_skill_trends](dbt/job_market_tracker/models/marts/job_skill_trends.sql)** (table)

Aggregates daily posting counts and skill keyword mentions by `load_date`. Skill detection uses `LIKE` pattern matching against job titles and category tags. Skills tracked reflect tools commonly listed in data analyst job descriptions:

- **Query and processing:** SQL, Python
- **BI and visualisation:** Power BI, Looker, Excel
- **Data engineering:** dbt, n8n

```sql
case when lower(title) like '%sql%'
    or lower(categories) like '%sql%' then 1 else 0 end as mentions_sql
```

### dbt Tests

Data quality tests are defined in [job_tracker__models](dbt/job_market_tracker/models/staging/job_tracker__models.yml) and verified with `dbt test`:

**[stg_job_tracker__raw_job_postings](dbt/job_market_tracker/models/staging/stg_job_tracker__raw_job_postings.sql) :**
- `guid`: not_null, unique
- `title`: not_null
- `seniority`: accepted_values (Intern, Entry-level, Mid-level, Senior)
- `employment_type`: accepted_values (Full Time, Part Time, Contractor, Temporary, Intern, Other)

### dbt Development Workflow

A recommended pattern when building new mart models: write and validate the SQL directly in MySQL Workbench first, confirm it returns the expected results, then paste the verified SQL into a dbt model file, replacing raw table references with `{{ source() }}` or `{{ ref() }}` references. Add tests and documentation in the YAML files, then run `dbt build` to materialise and test in one step.

### Running dbt

```bash
cd job_market_tracker
dbt debug    -- verify connection
dbt run      -- build all models
dbt test     -- run data quality tests
dbt build    -- run and test in one step
```

---

## Power BI Report

### Power Query Transformations

Before building the report, the following transformations were applied in Power Query Editor:

**`JobPostings` table (from [stg_job_tracker__raw_job_postings](dbt/job_market_tracker/models/staging/stg_job_tracker__raw_job_postings.sql) view)**
- `pub_date` confirmed as Date/Time type (conversion from Unix timestamp handled upstream in dbt using `FROM_UNIXTIME()`)
- `loaded_at` confirmed as Date/Time type
- `min_salary` and `max_salary` confirmed as Whole Number
- `guid` column removed (not needed for visualisation)
- A custom `seniority_sort` column added to enforce reading order (Intern=0, Entry-level=1, Mid-level=2, Senior=3, Other=4), then set as the Sort By Column for `seniority` in the data model
- Table renamed from `stg_job_tracker__raw_job_postings` to `JobPostings` for readability

**`SkillTrends` table (from [job_skill_trends](dbt/job_market_tracker/models/marts/job_skill_trends.sql))**
- Skill count columns unpivoted from wide format (one column per skill) to long format (one row per skill per day), producing `skill` and `mention_count` columns
- Skill column values cleaned from raw column names (e.g. `sql_count`) to readable labels (e.g. `SQL`) using Replace Values
- Count columns confirmed as Whole Number
- Table renamed from `job_skill_trends` to `SkillTrends`

Note: [job_seniority_salary](dbt/job_market_tracker/models/marts/job_seniority_salary.sql) was intentionally excluded from the Power BI data model. All salary calculations in the report are computed directly from `JobPostings` raw data using DAX measures, with currency and salary threshold filters applied inside each measure rather than at report level. This ensures salary filters only affect salary calculations without distorting count-based visuals such as Total Postings and seniority breakdowns.

### DAX Measures

All measures are stored in a dedicated `_Measures` table, separate from data tables, following Power BI best practice to keep the Fields pane organised and make it clear that calculations are intentionally separated from raw data columns.

**% Jobs With Salary Listed**
```dax
% Jobs With Salary Listed =
DIVIDE(
    COUNTROWS(FILTER(JobPostings, JobPostings[min_salary] <> BLANK())),
    COUNTROWS(JobPostings),
    0
)
```

**Avg Max Salary**
```dax
Avg Max Salary =
CALCULATE(
    AVERAGE(JobPostings[max_salary]),
    JobPostings[currency] = "USD",
    JobPostings[max_salary] >= 1000
)
```

**Avg Min Salary**
```dax
Avg Min Salary =
CALCULATE(
    AVERAGE(JobPostings[min_salary]),
    JobPostings[currency] = "USD",
    JobPostings[min_salary] >= 1000
)
```

**Full-Time Share**
```dax
Full-Time Share =
DIVIDE(
    CALCULATE(COUNTROWS('JobPostings'), 'JobPostings'[employment_type] = "Full Time"),
    [Total Postings],
    0
)
```

**Fully Transparent Postings**

Counts postings where both minimum and maximum salary are disclosed, giving a signal of how transparent the market is on compensation.

```dax
Fully Transparent Postings =
CALCULATE(
    COUNTROWS('JobPostings'),
    NOT(ISBLANK('JobPostings'[min_salary])) && NOT(ISBLANK('JobPostings'[max_salary]))
)
```

**Highest Max Salary (USD)**
```dax
Highest Max Salary (USD) =
CALCULATE(
    MAX(JobPostings[max_salary]),
    JobPostings[currency] = "USD",
    JobPostings[max_salary] >= 1000
)
```

**Last Data Ingestion**
```dax
Last Data Ingestion = MAX('JobPostings'[loaded_at])
```

**Top Skill**
```dax
Top Skill =
VAR TopSkillRow =
    TOPN(
        1,
        SUMMARIZE(SkillTrends, SkillTrends[skill], "Total", SUM(SkillTrends[mention_count])),
        [Total],
        DESC
    )
RETURN
    MAXX(TopSkillRow, SkillTrends[skill])
```

**Total Postings**
```dax
Total Postings = COUNTROWS(JobPostings)
```

### Page 1: [Data Analyst Market Demand & Job Landscapes](Screenshots/Job%20Tracker%20Power%20BI%20pg1_market_overview.jpg)
*The "Where Are the Jobs?" Page: a real-time snapshot of the hiring landscape, answering who is recruiting, at what seniority, under what employment terms, and how transparent they are about it.*

Top left (3 KPI cards, stacked horizontally): Total Job Postings, Jobs with Salary Listed, Most In-Demand Skill

Middle left: Horizontal bar chart: Postings by Seniority Level

Bottom left: Donut chart: Employment Type Breakdown

Bottom centre (3 multi-row cards): Last Data Ingestion, Full-Time Share, Fully Transparent Postings

Right (full height): Table: Top Hiring Companies sorted by posting count descending

### Page 2: [Compensation Deep Dive: Salary (USD) & Seniority](Screenshots/Job%20Tracker%20Power%20BI%20pg2_salary_seniority.jpg)
*The "What Does It Pay?" Page: an honest interrogation of compensation data, exposing salary ranges across seniority levels and employment types, filtered to USD annual-scale figures for a clean apples-to-apples comparison. Entry-level roles are absent from salary visuals because 0% of tracked entry-level postings disclosed compensation, itself a market signal worth noting.*

Top left (3 KPI cards, stacked vertically): Highest Max Salary Listed, Average Max Salary, Average Min Salary

Bottom left: Matrix: Salary by Seniority and Employment Type (Avg Min Salary, Avg Max Salary)

Top right: Clustered bar chart: Average Annual Salary Range by Seniority

Bottom right: Narrative text box: Key Takeaway, plain-English interpretation of salary findings including market ceiling observations, negotiation delta, and data disclosure caveat

**Layout principle:** each page follows a left-to-right information hierarchy: primary insight on the left, supporting detail on the right, matching natural reading flow and ensuring the most important numbers are visible first.

---

## Database Schema

```sql
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
```

**Design notes:**

- `guid UNIQUE NOT NULL`: enforces deduplication at the database level. MySQL rejects a second insert of the same job, and the n8n upsert node updates the existing row instead. 
- Auto-increment ID gaps in the `id` column are expected and normal: MySQL advances the counter on every insert attempt, including those converted to updates by the upsert logic.
- `pub_date VARCHAR(100)`: stored as text because the Himalayas API returns it as a raw Unix timestamp string. Conversion to datetime is deferred to the dbt staging layer using `FROM_UNIXTIME()`, keeping raw data in its original form, consistent with the ELT pattern.
- `loaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP`: tracks when each row entered the database, separate from `pub_date` (when the job was originally posted). Used to partition daily snapshots in dbt mart models.

---

## Design Decisions

**Why ELT and not ETL?**
Data is landed raw into MySQL first, then transformed by dbt. This separates ingestion from transformation: n8n handles reliability of delivery, dbt handles correctness of logic. Transformation failures do not block ingestion, and transformation logic is version-controlled, testable, and documented independently.

**Why upsert instead of insert-only?**
The Himalayas API returns the same active jobs across multiple daily pulls. Using INSERT OR UPDATE (upsert) on `guid` prevents duplicate rows without requiring a separate deduplication step, and keeps the latest job metadata current.

**Why dbt over plain SQL views?**
dbt provides version control, dependency management via `{{ ref() }}`, built-in testing, and documentation generation. The `{{ source() }}` reference in staging models means switching from MySQL to PostgreSQL later requires updating only the connection configuration, not the model SQL.

**Why apply salary filters inside DAX measures rather than at report level?**
A report-level salary threshold filter would exclude postings with no salary listed from all visuals, including count-based metrics like Total Postings and seniority charts. Embedding the filter inside salary-specific measures ensures it only affects salary calculations, keeping count visuals accurate.

**Why a dedicated `_Measures` table in Power BI?**
Keeping DAX measures in a dedicated table rather than attached to data tables follows Power BI best practice: it keeps the Fields pane organised and makes it immediately clear that calculations are intentionally separated from raw data columns.

---

## Known Limitations

**Self-hosted scheduling dependency**
n8n runs locally in Docker. The scheduled workflow only executes if Docker Desktop is running on the host machine at the scheduled time. Days when the machine is off result in skipped pipeline runs. A cloud-hosted deployment would eliminate this limitation.

**API returns 20 results per request**
The Himalayas API paginates at 20 results per call. The current implementation pulls only the first page (most recent postings). A future improvement would paginate through multiple pages to build a more comprehensive dataset.

**Skill detection is approximate**
Skill mentions are detected by `LIKE` pattern matching on job titles and category tags, not from structured skill fields. The Himalayas API does not provide an explicit required-skills field per posting. Skill counts are therefore a proxy metric, not a direct measure of employer demand.

**Salary data is incomplete**
Many postings do not list salary information. Entry-level postings in particular show 0% salary disclosure in current data, making entry-level compensation benchmarking impossible with this data source.

**Salary figures are multi-currency without conversion**
Salary figures are stored in their original currency. DAX measures filter to USD only, which excludes non-USD postings from salary visuals entirely rather than converting them. A currency conversion layer would be needed for a truly global salary comparison.

---

## Future Improvements

- **Paginate the API call** to pull more than 20 postings per daily run
- **Normalise categories into a junction table** (`job_categories`: one row per job per category) for accurate skill and category frequency analysis
- **Add a dbt singular test** to flag and exclude implausible salary values before they reach the mart layer
- **Add dbt source freshness check** to alert when the pipeline has not loaded new data within 25 hours
- **Migrate to PostgreSQL** for better dbt adapter support, richer SQL functions, and alignment with industry-standard analytics tooling
- **Cloud deployment**: host n8n on a VPS or cloud instance so the schedule runs reliably without depending on a local machine being switched on
- **Switch to a richer data source**: a job board API with structured skill fields per posting would produce more accurate and defensible skill demand analysis than keyword matching
- **Add currency conversion**: incorporate exchange rate data to enable true global salary comparisons rather than filtering to USD only
- **Add an AI-generated weekly summary**: an LLM API node in n8n to produce a plain-English narrative of market shifts, delivered via email

---

## How to Run Locally

### Prerequisites

- Docker Desktop
- MySQL 
- Python 3.10+
- dbt-core and dbt-mysql: `pip install dbt-core dbt-mysql`
- Power BI Desktop (Windows)

### 1. Start n8n

```bash
docker volume create n8n_data
docker run -d --name n8n -p 5678:5678 -v n8n_data:/home/node/.n8n docker.n8n.io/n8nio/n8n
```

Once the container is running, open a browser and navigate to `http://localhost:5678` on your own machine (this address resolves to your local machine only and is not accessible to anyone else). Complete the account setup, then import the workflow from [Job Tracker Workflow](n8n/Job%20Tracker%20Workflow.json) using the n8n interface (three-dot menu → Import workflow). Update the MySQL credential inside the workflow with your own database connection details before activating it.

### 2. Set up MySQL

Open MySQL Workbench, connect to your local MySQL instance, and run the SQL from [Job Tracker Schema](SQL/Job%20Tracker%20Schema.sql) to create the `job_market_tracker` database and `raw_job_postings` table.

### 3. Configure dbt

Create `~/.dbt/profiles.yml` (this file is not committed to the repo as it contains credentials):

```yaml
job_market_tracker:
  target: dev
  outputs:
    dev:
      type: mysql
      server: localhost
      port: 3306
      schema: job_market_tracker
      database: job_market_tracker
      username: your_username
      password: your_password
```

```bash
cd job_market_tracker
dbt debug
dbt build
```

### 4. Connect Power BI

Open [Job Tracker Power BI Report Template](Power%20BI/Job%20Tracker%20Power%20BI%20Report%20Template.pbix) in Power BI Desktop.   
> **Note**: This is a Power BI file (.pbix). Download and open with Power BI Desktop (free version available from Microsoft). The file cannot be previewed directly in VS Code or GitHub.  

Update the MySQL connection to point to your local instance via **Home → Transform data → Data source settings**.

---

## Data Attribution

Job data sourced from [Himalayas.app](https://himalayas.app). Per their API terms, data displayed from Himalayas must include a visible link back to himalayas.app.

---

## Author
**Linda Nyakasi**  
Certified Data Analyst  
[LinkedIn](https://www.linkedin.com/in/linda-nyakasi) | [GitHub](https://github.com/Linda-Nyakasi)
