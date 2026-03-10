# Pipeline Schema Contract

Canonical reference for field names at each stage of the automated pipeline.

## Stage 1: Job Scraper → Dejdash

**Endpoint:** `POST /api/scraper-ingest/runs/start` → `runs/{id}/jobs` → `runs/finish`

Per-job fields sent by the pydoll scraper:

| Field | Type | Example |
|---|---|---|
| `id` | string | `"abc123"` (hiring.cafe job ID) |
| `positionName` | string | `"Product Manager"` |
| `company` | string | `"Acme Corp"` |
| `location` | string | `"Remote, US"` |
| `description` | string | plain text (HTML stripped) |
| `url` | string | apply URL |
| `postedAt` | string | ISO date |
| `scrapedAt` | string | ISO datetime |
| `source` | string | `"hiring-cafe"` |
| `yearly_min_compensation` | number | `200000` |
| `yearly_max_compensation` | number | `250000` |
| `compensation_currency` | string | `"USD"` |
| `technical_tools` | string[] | `["Jira", "SQL"]` |
| `workplace_cities` | string[] | `["Remote"]` |
| `min_experience_years` | number | `5` |
| `is_compensation_transparent` | boolean | `true` |
| `estimated_publish_date` | string | ISO date |

## Stage 2: Dejdash ScrapedJob (MongoDB)

After normalization in `scraperIngestController.ingestJobs`:

| ScrapedJob Field | Derived From |
|---|---|
| `positionName` | `j.positionName \|\| j.title` |
| `company` | `j.company \|\| j.company_name` |
| `location` | `j.location` |
| `description` | `j.description \|\| j.description_stripped \|\| j.description_from_page` |
| `salary` | built from `yearly_min/max_compensation` |
| `experience` | `j.experience \|\| "${min_experience_years}+ years"` |
| `skills` | `j.skills \|\| j.technical_tools.join(', ')` |
| `qualifications` | `j.qualifications \|\| j.requirements_summary` |
| `responsibilities` | `j.responsibilities \|\| j.role_activities.join('; ')` |
| `url` | `j.url \|\| j.apply_url` |
| `sourceId` | `j.id` |
| `experienceMinYears` | `j.min_experience_years` |
| `extractedKeywords` | added by `process_jobs.py` (OpenAI) |

## Stage 3: Dejdash → Resume API

**Endpoint:** `POST {api_url}/jobs/json`

Built by `pipelineService.formatJobForApi`:

| Resume API Field | ScrapedJob Source |
|---|---|
| `id` | `sourceId` |
| `Title` | `positionName` |
| `Company` | `company` |
| `Description` | `description` |
| `Location` | `location` |
| `Salary` | `salary` |
| `Technologies` | `skills` |
| `Qualifications` | `qualifications` |
| `Duties` | `responsibilities` |
| `ATS_Keywords` | `extractedKeywords` |
| `URL` | `url` |
| `Experience` | `experience` |

Top-level request fields:

| Field | Source |
|---|---|
| `resume_config` | `ResumeConfig.resume_config` |
| `google_drive_config` | `ResumeConfig.google_drive_config` (only if `template_id` present) |
| `source_run_id` | `PipelineJob.sourceRunId` |
| `source_config_id` | `ResumeConfig._id` |

## Stage 4: Resume API Job Status

**Endpoint:** `GET /jobs/{job_id}`

| Field | When | Description |
|---|---|---|
| `status` | always | `"processing"`, `"completed"`, or `"failed"` |
| `progress` | always | 0-100 |
| `current_stage` | processing | e.g. `"Direct Resume Generation"`, `"Google Drive Integration"` |
| `elapsed_minutes` | processing | time since start |
| `result_path` | completed | path to structured CSV |
| `output_folder_id` | completed + Drive | Google Drive root folder ID |
| `google_drive_folder_id` | completed + Drive | Resumes subfolder ID |
| `tracking_sheet_id` | completed + Drive | Tracking sheet ID |
| `tracking_sheet_url` | completed + Drive | Tracking sheet URL |
| `resumes_folder_url` | completed + Drive | Resumes folder URL |
| `total_resumes_created` | completed + Drive | count |
| `error` | failed | error message |

## Stage 5: Resume Data in MongoDB

Written by `dejdash_integration.save_resume_data`:

| MongoDB Field | Source |
|---|---|
| `sourceJobId` | `id` from JobData (hiring.cafe job ID) |
| `jobTitle` | `Title` |
| `company` | `Company` |
| `jobDescription` | `Description` |
| `location` | `Location` |
| `jobUrl` | `URL` |
| `atsKeywords` | `ATS_Keywords` |
| `technologies` | `Technologies` |
| `qualifications` | `Qualifications` |
| `duties` | `Duties` |
| `resumeStatements` | parsed from `Job1Statement1`...`JobNStatementM` |
| `technicalSkillsList` | `Technical Skills List` (generated) |
| `resumeSummary` | `Resume Summary` (generated) |
| `similarTitles` | `Role Title 1`...`Role Title 5` (generated) |
| `resumeConfigId` | from `source_config_id` |
| `resumeConfigName` | from config |
| `resumeApiJobId` | batch job ID |
| `sourceRunId` | from `source_run_id` |

## Google Drive Folder Persistence

- Each `ResumeConfig` stores `google_drive_config.output_folder_id`
- First run: resume API creates folder, returns ID via `/jobs/{id}` status
- `pipelineService` saves `output_folder_id` back to `ResumeConfig`
- Subsequent runs: same folder ID passed, resumes added to existing folder
- Tracking sheet: found and appended to (not recreated) when folder exists
