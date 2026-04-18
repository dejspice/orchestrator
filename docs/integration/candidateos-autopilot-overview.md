# CandidateOS ↔ Autopilot Integration Overview

This document is a workspace-level coordination reference for how
[dejdash](../../repos/dejdash) (CandidateOS) and
[agentic-job](../../repos/agentic-job) (Autopilot) interact.

It describes high-level flow, ownership boundaries, key endpoints, and shared
environment variables. It is **not** a specification of either repo's internal
structure — each repo remains independently owned and independently deployable.

## High-level flow

```
dejdash/CandidateOS
   │
   │  operator clicks "Automate" on an application
   ▼
POST /api/applications/:id/automate   (dejdash backend)
   │
   │  dejdash enqueues run, forwards to Autopilot
   ▼
agentic-job Autopilot API
   │
   │  schedules a Temporal workflow
   ▼
Temporal (workflow orchestrator)
   │
   │  dispatches work to the Worker
   ▼
agentic-job Worker
   │   - browser automation
   │   - external portal interactions
   │   - emits run status + verification artifacts
   ▼
Run status / verification code
   │
   │  polled / pushed back to dejdash
   ▼
dejdash/CandidateOS
   │
   │  updates application state, surfaces attention,
   │  drives retries and verification UX for the operator
   ▼
Operator
```

## Ownership boundaries

- **dejdash / CandidateOS** — operator-facing workflow
  - Application queue and attention state
  - Retry / escalation policy
  - Verification UX (entering codes, approving steps)
  - Persistence of applications, runs, artifacts in dejdash MongoDB
  - Source of truth for "what should happen next for this candidate"

- **agentic-job / Autopilot** — execution engine
  - Temporal workflows and activities
  - Browser automation runners
  - Run lifecycle and run status reporting
  - Verification code capture from target portals
  - Source of truth for "how the automation actually ran"

Neither side owns the other's data. Communication is over documented HTTP
endpoints only.

## Key endpoints

### dejdash (CandidateOS) — backend

- `POST /api/applications/:id/automate` — start an Autopilot run for an application.
- `GET  /api/applications/:id/automation-status` — current run status as seen by CandidateOS.
- `POST /api/applications/:id/verification-code` — operator supplies a verification
  code captured in the CandidateOS UI; relayed to Autopilot.

### agentic-job (Autopilot) — API

- `GET  /api/runs/:id/status` — raw run status from Autopilot (workflow-level).
- `POST /api/runs/:id/verification-code` — submit a verification code to the
  in-flight workflow that is waiting on it.

CandidateOS endpoints are the public contract used by the frontend and other
clients. Autopilot endpoints are consumed by CandidateOS backend and, where
appropriate, the Autopilot UI.

## Key environment variables

These must be configured in the respective deployments. They are **not**
shared through a monorepo build — each repo reads them from its own
environment.

| Variable                        | Consumer       | Purpose                                                  |
|---------------------------------|----------------|----------------------------------------------------------|
| `AUTOPILOT_API_URL`             | dejdash        | Base URL for agentic-job Autopilot API                   |
| `AUTOPILOT_API_KEY`             | dejdash        | Server-to-server auth to Autopilot                       |
| `NEXT_PUBLIC_AUTOPILOT_UI_URL`  | dejdash (web)  | Deep links from CandidateOS UI into Autopilot UI         |
| `TEMPORAL_ADDRESS`              | agentic-job    | Temporal cluster address used by Autopilot + Worker      |
| `TEMPORAL_NAMESPACE`            | agentic-job    | Temporal namespace for Autopilot workflows               |

## Active branches (workspace tracking)

The orchestrator tracks the following feature branches for active
cross-repo work. See `.gitmodules` for the authoritative list.

| Submodule                     | Path                           | Branch                                          |
|-------------------------------|--------------------------------|-------------------------------------------------|
| dejdash                       | `repos/dejdash`                | `cursor/autopilot-running-observability-5f1a`   |
| agentic-job                   | `repos/agentic-job`            | `cursor/restore-temporal-runtime-8f3b`          |
| job-scraper                   | `repos/job-scraper`            | `main`                                          |
| resume-generator-project      | `repos/resume-generator-project` | `main`                                        |

## Non-goals

The orchestrator repo explicitly does **not**:

- merge the two codebases
- introduce Nx / Turborepo / other monorepo tooling
- share `package.json` / `node_modules` across repos
- copy source files between repos
- change deployment configuration inside any child repo

Each child repo stays independently deployable and independently owned.
