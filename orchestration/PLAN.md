# Pipeline Alignment Plan

Status: **All gaps implemented and merged.** `feat/pipeline-alignment` branches are up-to-date with their tracked branches.
Next: deploy, create PipelineConfig docs in MongoDB, test live.

## Deployment Map

| Service | Railway URL | Repo | Notes |
|---|---|---|---|
| **Scraper API** | `job-scraper-production-2069.up.railway.app` | job-scraper (`api_server.py`) | `POST /scrape` triggers scrapes |
| **Dejdash Backend** | `dejdash-production.up.railway.app` | dejdash (`backend/`) | Event bus + pipeline service |
| **Pydoll/Legacy Backend** | `fat-parcel-production.up.railway.app` | dejdash (older deploy?) | Scrapers currently point here |
| **Resume Generator API** | `resume-generator-api-5nq62.ondigitalocean.app` | resume-generator-project (`api/`) | Default in pipelineService.js |
| **Dashboard Frontend** | `dejdash.vercel.app` | dejdash (`frontend_new/`) | Vercel |

### URL Configuration

Scrapers now read `RAILWAY_API_URL` from the environment, falling back to the hardcoded default (`fat-parcel-production`). Set `RAILWAY_API_URL` on Railway to point to whichever backend runs the event bus and pipeline service.

The pipeline service (`pipelineService.js`) resolves the resume API URL in this order:
1. `ResumeConfig.api_settings.api_url` (per-config)
2. `process.env.RESUME_API_URL` (env var)
3. `https://resume-generator-api-5nq62.ondigitalocean.app` (hardcoded fallback)

The `uploadAndProcess` legacy path also follows this chain (previously fell back to `localhost`).

## What Was Implemented

### Gap 1: `id` flows end-to-end
- Added `id: Optional[str]` to `JobData` in resume API
- Threaded through `process_single_job_direct` → `format_resume_data` → `save_resume_data`
- Stored as `sourceJobId` in MongoDB resume documents
- All ingestion paths (ingestJobs, uploadAndProcess, pipeline/run) extract and store `sourceId`

### Gap 2: `experience` derived from `min_experience_years`
- All three ingestion paths (`ingestJobs`, `uploadAndProcess`, `pipelineController.run`) fall back to `"${min_experience_years}+ years"`

### Gap 3: Cron routed through event bus
- Both scrapers (`hiring_cafe_scraper.py`, `hiring_cafe_scraper_pydoll.py`) always use the 3-step ingest
- `finishRun` emits `SCRAPE_RUN_COMPLETED` → pipeline auto-process handles the rest

### Gap 4: `output_folder_id` captured in job status
- `process_jobs_directly` reads `output_summary.json` after Google Drive subprocess
- Stores `output_folder_id`, `google_drive_folder_id`, `tracking_sheet_id`, etc. in `active_jobs`
- Pipeline service polls this and saves `output_folder_id` back to `ResumeConfig`

### Gap 5: Tracking sheet accumulates
- Added `find_existing_tracking_sheet`, `append_to_tracking_sheet`, `get_tracking_sheet_row_count`
- When `output_folder_id` is provided, finds existing sheet and appends rows
- Sequence numbering continues from last entry

### Gap 6: Env-based configuration for scrapers
- Both scrapers read `RAILWAY_API_URL`, `RAILWAY_API_KEY`, `SOURCE_NAME` from env
- Defaults preserved as fallback — no breaking change for existing deployments
- Railway deployments can now target different backends without code changes

### Gap 7: uploadAndProcess aligned with pipeline contract
- Now passes `source_run_id` and `source_config_id` to resume API
- Includes `id` (sourceId) and `Experience` in formatted job payload
- Uses consistent `RESUME_API_URL` resolution (env → config → fallback)
- Uses `sourceId` in urlHash for dedup consistency

## Full Pipeline Flow

```
1. POST /scrape on job-scraper API
   ↓
2. Scraper runs → collects jobs from hiring.cafe
   ↓
3. 3-step ingest to dejdash backend:
   POST /api/scraper-ingest/runs/start    → get runId
   POST /api/scraper-ingest/runs/{id}/jobs → upload jobs
   POST /api/scraper-ingest/runs/finish    → emit SCRAPE_RUN_COMPLETED
   ↓
4. Event bus triggers auto-process listener
   ↓
5. For each matching PipelineConfig:
   a. Keyword extraction (process_jobs.py + OpenAI)
   b. Dedup check against resume API
   c. Submit to resume API: POST /jobs/json
   d. Poll GET /jobs/{id} until completion
   ↓
6. Resume API processes each job:
   a. Generate resume statements (OpenAI)
   b. Generate skills, summary, similar titles
   c. Write to MongoDB via dejdash_integration.py
   d. Optional: Google Drive integration (create docs, tracking sheet)
   ↓
7. Pipeline service captures output_folder_id, links resume docs
   ↓
8. Frontend displays results at dejdash.vercel.app
```

## What Still Needs to Happen (Deployment Steps)

### 1. Merge feature branches to production

```bash
# job-scraper: feat/pipeline-alignment → main
# dejdash: feat/pipeline-alignment → staging
# resume-generator-project: feat/pipeline-alignment → main
```

### 2. Set environment variables on Railway

**Scraper API (`job-scraper-production`):**
- `RAILWAY_API_URL` — URL of the dejdash backend that runs the event bus
- `RAILWAY_API_KEY` — API key matching `DEJDASH_API_KEY` on the backend
- `SOURCE_NAME` — (optional) override default source name per deployment

**Dejdash Backend (`dejdash-production`):**
- `MONGODB_URI` — shared MongoDB connection
- `DEJDASH_API_KEY` — API key for scraper-ingest and pipeline endpoints
- `RESUME_API_URL` — (optional) override resume API base URL
- `RESUME_API_KEY` — (optional) API key for resume API
- `OPENAI_API_KEY` — for keyword extraction

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
  "sourceFilters": {
    "sources": ["hiring-cafe-pydoll-scraper"]
  },
  "processingSettings": {
    "model_name": "gpt-4o-mini",
    "batch_size": 20
  }
}
```

**Template per person:** Each person who wants resumes from the same scrape gets their own ResumeConfig (with their template_id) and their own PipelineConfig.

**Source filtering:** Set `sourceFilters.sources` to match the scraper's `SOURCE_NAME`. The pydoll scraper defaults to `"hiring-cafe-pydoll-scraper"` and can be overridden via the `SOURCE_NAME` env var per cron job.

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

Verify the chain:
1. Jobs appear in dejdash scraper dashboard
2. `SCRAPE_RUN_COMPLETED` event fires (check `/api/pipeline/status`)
3. PipelineConfig auto-triggers (check `/api/pipeline/jobs/active`)
4. Keywords extracted, resumes generated, written to MongoDB
5. Resumes visible in dejdash frontend

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
| **dejdash** | `backend/controllers/scraperIngestController.js`, `backend/controllers/pipelineController.js`, `backend/services/pipelineService.js`, `backend/services/eventBus.js` |
| **resume-generator-project** | `api/resume_api.py`, `dejdash_integration.py`, `api/google_drive_integration.py` |
| **orchestrator** | `contracts/pipeline-schema.md`, `orchestration/PLAN.md` |
