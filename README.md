# orchestrator

Parent repo that ties together the job-search pipeline via git submodules.
Launch Cursor cloud agents against this repo to work across all three projects.

## Workspace Map

| Submodule | Path | Branch | Purpose |
|---|---|---|---|
| [job-scraper](https://github.com/dejspice/job-scraper) | `repos/job-scraper` | `main` | Pydoll-based scraper that pulls job listings from hiring.cafe |
| [dejdash](https://github.com/dejspice/dejdash) | `repos/dejdash` | `cursor/autopilot-running-observability-5f1a` | Node/React dashboard (CandidateOS) — receives scraped jobs, displays results |
| [resume-generator-project](https://github.com/dejspice/resume-generator-project) | `repos/resume-generator-project` | `main` | Serverless resume generator (AWS Lambda + S3 + DynamoDB) |
| [agentic-job](https://github.com/dejspice/agentic-job) | `repos/agentic-job` | `cursor/restore-temporal-runtime-8f3b` | Autopilot automation engine — Temporal workflows + Worker + browser automation |

## Data Flow

```
job-scraper  ──scrape──►  dejdash backend (Railway API)
                              │
                              ▼
                     dejdash frontend (Vercel)
                              │
                              ▼
              resume-generator-project
              (generates tailored resumes per job)
                              │
                              ▼
                     dejdash MongoDB
                     (stores resume output)
```

## Key Integration Points

- **job-scraper → dejdash**: Uploads scraped jobs via `POST /api/scraper-ingest/upload-and-process` on the Railway backend.
- **resume-generator-project → dejdash**: `dejdash_integration.py` writes processed resume data back to the shared MongoDB instance.
- **Shared config**: `config.json` in both dejdash and resume-generator-project controls processing behaviour.

## Tech Stack

| Repo | Runtime | Hosting |
|---|---|---|
| job-scraper | Python 3.10+ | Local / Docker / cron |
| dejdash backend | Node.js 14+ (Express) | Railway |
| dejdash frontend | React | Vercel |
| resume-generator-project | Python 3.9+ (Lambda) | AWS (API Gateway, Lambda, S3, SQS, DynamoDB) |

## Setup

```bash
git clone --recurse-submodules https://github.com/dejspice/orchestrator.git
cd orchestrator

# Ensure submodules are on their tracked branches
git submodule update --remote --merge
```

## Directory Layout

```
orchestrator/
├── repos/
│   ├── job-scraper/              # scraping service
│   ├── dejdash/                  # dashboard UI + backend (CandidateOS)
│   ├── resume-generator-project/ # resume generation
│   └── agentic-job/              # Autopilot — Temporal + browser automation
├── docs/
│   └── integration/              # cross-repo integration docs
│       └── candidateos-autopilot-overview.md
├── orchestration/
│   ├── prompts/                  # reusable agent prompts
│   └── scripts/                  # cross-repo automation scripts
├── contracts/                    # shared schemas / API contracts
├── AGENTS.md                     # cloud agent instructions
└── README.md                     # this file
```
