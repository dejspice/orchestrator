# Pipeline Alignment Plan

Status: **All 5 gaps implemented** on `feat/pipeline-alignment` branches.
Next: merge to tracked branches, create PipelineConfig docs in MongoDB, test live.

## Deployment Map

| Service | Railway URL | Repo | Notes |
|---|---|---|---|
| **Scraper API** | `job-scraper-production-2069.up.railway.app` | job-scraper (`api_server.py`) | `POST /scrape` triggers scrapes |
| **Dejdash Backend** | `dejdash-production.up.railway.app` | dejdash (`backend/`) | Event bus + pipeline service |
| **Pydoll/Legacy Backend** | `fat-parcel-production.up.railway.app` | dejdash (older deploy?) | Scrapers currently point here |
| **Resume Generator API** | `resume-generator-api-5nq62.ondigitalocean.app` | resume-generator-project (`api/`) | Default in pipelineService.js |
| **Dashboard Frontend** | `dejdash.vercel.app` | dejdash (`frontend_new/`) | Vercel |

### URL Configuration

All scrapers currently hardcode `API_URL` to `fat-parcel-production.up.railway.app`. If the event bus and pipeline service are on `dejdash-production.up.railway.app` instead, the scraper `API_URL` needs updating.

The pipeline service (`pipelineService.js`) resolves the resume API URL in this order:
1. `ResumeConfig.api_settings.api_url` (per-config)
2. `process.env.RESUME_API_URL` (env var)
3. `https://resume-generator-api-5nq62.ondigitalocean.app` (hardcoded fallback)

## What Was Implemented (feat/pipeline-alignment)

### Gap 1: `id` flows end-to-end
- Added `id: Optional[str]` to `JobData` in resume API
- Threaded through `process_single_job_direct` → `format_resume_data` → `save_resume_data`
- Stored as `sourceJobId` in MongoDB resume documents

### Gap 2: `experience` derived from `min_experience_years`
- Both `ingestJobs` and `uploadAndProcess` in `scraperIngestController.js` now fall back to `"${min_experience_years}+ years"`

### Gap 3: Cron routed through event bus
- Both scrapers (`hiring_cafe_scraper.py`, `hiring_cafe_scraper_pydoll.py`) now always use the 3-step process
- `finishRun` emits `SCRAPE_RUN_COMPLETED` → pipeline auto-process handles the rest

### Gap 4: `output_folder_id` captured in job status
- `process_jobs_directly` reads `output_summary.json` after Google Drive subprocess
- Stores `output_folder_id`, `google_drive_folder_id`, `tracking_sheet_id`, etc. in `active_jobs`
- Pipeline service polls this and saves `output_folder_id` back to `ResumeConfig`

### Gap 5: Tracking sheet accumulates
- Added `find_existing_tracking_sheet`, `append_to_tracking_sheet`, `get_tracking_sheet_row_count`
- When `output_folder_id` is provided, finds existing sheet and appends rows
- Sequence numbering continues from last entry

## What Still Needs to Happen

### 1. Merge feature branches

```bash
# job-scraper: feat/pipeline-alignment → main
# dejdash: feat/pipeline-alignment → staging
# resume-generator-project: feat/pipeline-alignment → main
# orchestrator: feat/pipeline-alignment → main
```

### 2. Verify/update API_URL in scrapers

Confirm whether scrapers should point to `fat-parcel-production` or `dejdash-production`. The event bus and pipeline service must be on the same backend that receives the scraper's 3-step calls.

### 3. Create PipelineConfig documents in MongoDB

Each config name needs a `PipelineConfig` document linked to its `ResumeConfig`. Create via:

```
POST https://<dejdash-backend>/api/pipeline/configs
x-api-key: <api-key>

{
  "name": "pm-remote-auto",
  "description": "Auto-process pm-remote scrape runs",
  "resumeConfigId": "<ObjectId of pm-remote ResumeConfig>",
  "enabled": true,
  "autoProcessOnScrapeComplete": true,
  "mode": "async",
  "sourceFilters": {},
  "processingSettings": {
    "model_name": "gpt-4o-mini",
    "batch_size": 20
  }
}
```

**Template per person:** Each person who wants resumes from the same scrape gets their own ResumeConfig (with their template_id) and their own PipelineConfig.

**Source filtering:** To prevent ALL configs from triggering on every scrape, set `sourceFilters.sources` to match the scraper's `SOURCE_NAME`. Currently all scrapers use `"hiring-cafe-pydoll-scraper"` — can be differentiated per cron job if needed.

### 4. Test with a small manual scrape

```
POST https://job-scraper-production-2069.up.railway.app/scrape
x-api-key: <scraper-api-key>

{
  "url": "https://hiring.cafe/?query=product+manager&workplaceType=remote",
  "config_name": "pm-remote",
  "max_jobs": 3
}
```

### 5. Set up Railway cron jobs

Configure scheduled triggers in Railway that call `POST /scrape` on the scraper API with the appropriate URL and config_name for each job type.

## Config Name Registry

| Config Name | Cron Schedule | Search Query |
|---|---|---|
| `pm-remote` | Daily 8:15 PM UTC | Product Manager, remote |
| `swe-remote` | Daily 8:16 PM UTC | Software Engineer, remote |
| `sales-remote` | Daily 8:17 PM UTC | Sales, remote |
| `hr-remote` | Daily 8:18 PM UTC | HR Manager, remote |

## File Change Summary

| Repo | Files Changed |
|---|---|
| **job-scraper** | `hiring_cafe_scraper.py`, `hiring_cafe_scraper_pydoll.py` |
| **dejdash** | `backend/controllers/scraperIngestController.js` |
| **resume-generator-project** | `api/resume_api.py`, `dejdash_integration.py`, `api/google_drive_integration.py` |
| **orchestrator** | `contracts/pipeline-schema.md`, `orchestration/PLAN.md` |
