# Agent Instructions

This is a multi-repo workspace managed via git submodules.
All three repos live under `repos/` and are connected by a shared data pipeline.

## Repo Overview

- **repos/job-scraper** (Python) — scrapes job listings from hiring.cafe using Pydoll browser automation. Uploads results to the dejdash Railway API.
- **repos/dejdash** (Node.js backend + React frontend) — the central dashboard. Backend on Railway receives scraped jobs; frontend on Vercel displays them.
- **repos/resume-generator-project** (Python, AWS serverless) — takes job listings, generates tailored resumes via Lambda, stores results back in dejdash's MongoDB.

## Tracked Branches

| Repo | Branch | Notes |
|---|---|---|
| job-scraper | `main` | Production |
| dejdash | `staging` | Active development branch |
| resume-generator-project | `main` | Production |

When working on dejdash, always target the `staging` branch.

## Data Flow

```
job-scraper  →  dejdash backend (Railway)  →  dejdash frontend (Vercel)
                                            →  resume-generator-project (AWS)
                                                      ↓
                                               dejdash MongoDB
```

## Cross-Repo Rules

1. **If scraper output format changes** (fields added/removed in `hiring_cafe_scraper.py`):
   - Verify dejdash backend ingestion still works (`/api/scraper-ingest/upload-and-process`)
   - Check resume-generator-project still parses the data correctly

2. **If resume schema changes** (output of `resume_resume_generator.py` or `dejdash_integration.py`):
   - Update dejdash backend models and frontend display components

3. **If dejdash API endpoints change** (routes in `repos/dejdash/backend/routes/`):
   - Update the `API_URL` and endpoint paths in job-scraper
   - Update any references in resume-generator-project

4. **Run tests in each touched repo** before considering work complete.

## Key Files

| What | Where |
|---|---|
| Scraper entry point | `repos/job-scraper/hiring_cafe_scraper.py` |
| Scraper API upload | `repos/job-scraper/api_server.py` |
| Dashboard backend | `repos/dejdash/backend/server.js` |
| Dashboard routes | `repos/dejdash/backend/routes/` |
| Dashboard frontend | `repos/dejdash/frontend_new/` |
| Resume generator | `repos/resume-generator-project/resume_resume_generator.py` |
| Dejdash integration | `repos/resume-generator-project/dejdash_integration.py` |
| Resume API | `repos/resume-generator-project/resume_api.py` |

## Environment & Config

- dejdash and resume-generator-project share a MongoDB instance (connection string via `MONGODB_URI` env var)
- job-scraper targets the Railway backend at the URL in its config (`API_URL`)
- resume-generator-project uses AWS credentials for Lambda/S3/DynamoDB access
- Never commit `.env` files or credentials

## Conventions

- Commit messages should reference which repo is affected, e.g. `[dejdash] fix filter endpoint`
- When making cross-repo changes, describe the full change set in the PR body
- Prefer small, focused changes over large cross-cutting PRs
