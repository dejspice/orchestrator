#!/usr/bin/env bash
#
# End-to-end pipeline test: trigger a small scrape and monitor the pipeline.
#
# Usage:
#   export DEJDASH_API_URL="https://your-dejdash-backend.up.railway.app"
#   export DEJDASH_API_KEY="your-api-key"
#   export SCRAPER_API_URL="https://job-scraper-production-2069.up.railway.app"
#   export SCRAPER_API_KEY="your-scraper-api-key"
#   ./test_pipeline.sh [search_url] [max_jobs]
#
set -euo pipefail

DEJDASH_URL="${DEJDASH_API_URL:?Set DEJDASH_API_URL}"
DEJDASH_KEY="${DEJDASH_API_KEY:?Set DEJDASH_API_KEY}"
SCRAPER_URL="${SCRAPER_API_URL:?Set SCRAPER_API_URL}"
SCRAPER_KEY="${SCRAPER_API_KEY:?Set SCRAPER_API_KEY}"

SEARCH_URL="${1:-https://hiring.cafe/?query=product+manager&workplaceType=remote}"
MAX_JOBS="${2:-3}"

echo "========================================"
echo " Pipeline End-to-End Test"
echo "========================================"
echo "Scraper:  ${SCRAPER_URL}"
echo "Backend:  ${DEJDASH_URL}"
echo "Search:   ${SEARCH_URL}"
echo "Max jobs: ${MAX_JOBS}"
echo ""

# ── Pre-flight checks ─────────────────────────────────────────────────
echo "1. Pre-flight checks..."

HEALTH=$(curl -sf "${DEJDASH_URL}/api/health" 2>&1 || true)
if ! echo "$HEALTH" | grep -q '"status":"OK"'; then
    echo "   ❌ Backend not reachable"
    exit 1
fi
echo "   ✅ Backend healthy"

BUS=$(curl -sf "${DEJDASH_URL}/api/pipeline/status" -H "x-api-key: ${DEJDASH_KEY}" 2>&1 || true)
AUTO_COUNT=$(echo "$BUS" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['autoProcessConfigsEnabled'])" 2>/dev/null || echo "0")
echo "   Auto-process configs: ${AUTO_COUNT}"
if [ "$AUTO_COUNT" = "0" ]; then
    echo "   ⚠️  No auto-process PipelineConfigs! Pipeline won't trigger automatically."
    echo "   Run create_pipeline_config.sh first."
fi

SCRAPER_HEALTH=$(curl -sf "${SCRAPER_URL}/health" 2>&1 || true)
if echo "$SCRAPER_HEALTH" | grep -q 'healthy\|ok\|status'; then
    echo "   ✅ Scraper API healthy"
else
    echo "   ❌ Scraper API not reachable at ${SCRAPER_URL}"
    exit 1
fi
echo ""

# ── Trigger scrape ────────────────────────────────────────────────────
echo "2. Triggering scrape (${MAX_JOBS} jobs)..."
SCRAPE_RESPONSE=$(curl -sf -X POST "${SCRAPER_URL}/scrape" \
    -H "Content-Type: application/json" \
    -H "x-api-key: ${SCRAPER_KEY}" \
    -d "{\"url\": \"${SEARCH_URL}\", \"config_name\": \"test\", \"max_jobs\": ${MAX_JOBS}}" 2>&1)

JOB_ID=$(echo "$SCRAPE_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('job_id',''))" 2>/dev/null || echo "")

if [ -z "$JOB_ID" ]; then
    echo "   ❌ Failed to trigger scrape"
    echo "   $SCRAPE_RESPONSE"
    exit 1
fi

echo "   ✅ Scrape queued: job_id=${JOB_ID}"
echo ""

# ── Poll scrape status ────────────────────────────────────────────────
echo "3. Waiting for scrape to complete..."
for i in $(seq 1 60); do
    sleep 10
    STATUS=$(curl -sf "${SCRAPER_URL}/jobs/${JOB_ID}" \
        -H "x-api-key: ${SCRAPER_KEY}" 2>&1 || echo '{}')
    SCRAPE_STATUS=$(echo "$STATUS" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status','unknown'))" 2>/dev/null || echo "unknown")

    echo "   [${i}0s] Status: ${SCRAPE_STATUS}"

    if [ "$SCRAPE_STATUS" = "completed" ]; then
        JOBS_SCRAPED=$(echo "$STATUS" | python3 -c "import sys,json; print(json.load(sys.stdin).get('jobs_scraped',0))" 2>/dev/null || echo "?")
        echo "   ✅ Scrape complete: ${JOBS_SCRAPED} jobs"
        break
    elif [ "$SCRAPE_STATUS" = "failed" ]; then
        echo "   ❌ Scrape failed"
        echo "   $STATUS"
        exit 1
    fi
done
echo ""

# ── Check for pipeline activity ───────────────────────────────────────
echo "4. Checking pipeline activity..."
sleep 5
ACTIVE=$(curl -sf "${DEJDASH_URL}/api/pipeline/jobs/active" \
    -H "x-api-key: ${DEJDASH_KEY}" 2>&1 || echo '{"data":[]}')
ACTIVE_COUNT=$(echo "$ACTIVE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('count',0))" 2>/dev/null || echo "0")

echo "   Active pipeline jobs: ${ACTIVE_COUNT}"

if [ "$ACTIVE_COUNT" -gt 0 ]; then
    echo "   ✅ Pipeline triggered! Monitoring progress..."
    echo "$ACTIVE" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for job in data.get('data', []):
    print(f\"   Pipeline job: {job['_id']} status={job['status']} total={job.get('totalJobs',0)} processed={job.get('processedJobs',0)}\")
" 2>/dev/null || true
else
    echo "   ⚠️  No active pipeline jobs yet. Checking recent jobs..."
    RECENT=$(curl -sf "${DEJDASH_URL}/api/pipeline/jobs?limit=5" \
        -H "x-api-key: ${DEJDASH_KEY}" 2>&1 || echo '{"data":[]}')
    echo "$RECENT" | python3 -c "
import sys, json
data = json.load(sys.stdin)
jobs = data.get('data', [])
if not jobs:
    print('   (no pipeline jobs found)')
for job in jobs:
    print(f\"   {job['_id']} status={job['status']} trigger={job.get('trigger','?')} total={job.get('totalJobs',0)}\")
" 2>/dev/null || true
fi
echo ""

# ── Check recent scrape runs ──────────────────────────────────────────
echo "5. Recent scrape runs in dejdash:"
RUNS=$(curl -sf "${DEJDASH_URL}/api/scraper-ingest/runs" \
    -H "x-api-key: ${DEJDASH_KEY}" 2>&1 || echo '{"data":[]}')
echo "$RUNS" | python3 -c "
import sys, json
data = json.load(sys.stdin)
runs = data.get('data', [])[:5]
if not runs:
    print('   (no runs found)')
for r in runs:
    print(f\"   {r['_id']} status={r.get('status','?')} jobs={r.get('jobCount',0)} source={r.get('source','?')} processed={r.get('isProcessed',False)}\")
" 2>/dev/null || echo "   (could not parse)"
echo ""

echo "========================================"
echo " Test complete. Check the dashboard at:"
echo " https://dejdash.vercel.app/scraper"
echo "========================================"
