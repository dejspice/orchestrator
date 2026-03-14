#!/usr/bin/env bash
#
# Full pipeline setup script.
#
# Usage:
#   export DEJDASH_API_URL="https://your-dejdash-backend.up.railway.app"
#   export DEJDASH_API_KEY="your-api-key"
#   ./setup_pipeline.sh
#
# What it does:
#   1. Checks the backend health and event bus status
#   2. Lists existing ResumeConfigs so you can pick one
#   3. Creates a PipelineConfig with autoProcessOnScrapeComplete=true
#   4. Verifies the auto-process listener is active
#
set -euo pipefail

API_URL="${DEJDASH_API_URL:?Set DEJDASH_API_URL to your dejdash backend URL}"
API_KEY="${DEJDASH_API_KEY:?Set DEJDASH_API_KEY to your dejdash API key}"

HEADERS=(-H "Content-Type: application/json" -H "x-api-key: ${API_KEY}")

echo "========================================"
echo " Pipeline Setup"
echo "========================================"
echo "Backend: ${API_URL}"
echo ""

# ── Step 1: Health check ───────────────────────────────────────────────
echo "1. Checking backend health..."
HEALTH=$(curl -sf "${API_URL}/api/health" 2>&1 || true)
if echo "$HEALTH" | grep -q '"status":"OK"'; then
    DB_STATE=$(echo "$HEALTH" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('database',{}).get('state','unknown'))" 2>/dev/null || echo "unknown")
    echo "   ✅ Backend is up (DB: ${DB_STATE})"
else
    echo "   ❌ Backend is not reachable at ${API_URL}"
    echo "   Response: ${HEALTH}"
    exit 1
fi
echo ""

# ── Step 2: Event bus status ───────────────────────────────────────────
echo "2. Checking event bus status..."
BUS_STATUS=$(curl -sf "${API_URL}/api/pipeline/status" "${HEADERS[@]}" 2>&1 || true)
if echo "$BUS_STATUS" | grep -q '"success":true'; then
    AUTO_CONFIGS=$(echo "$BUS_STATUS" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data']['autoProcessConfigsEnabled'])" 2>/dev/null || echo "?")
    LISTENERS=$(echo "$BUS_STATUS" | python3 -c "import sys,json; d=json.load(sys.stdin); print(json.dumps(d['data']['listeners']))" 2>/dev/null || echo "{}")
    echo "   ✅ Event bus active"
    echo "   Auto-process configs enabled: ${AUTO_CONFIGS}"
    echo "   Listeners: ${LISTENERS}"
else
    echo "   ⚠️  Could not fetch event bus status"
fi
echo ""

# ── Step 3: List ResumeConfigs ─────────────────────────────────────────
echo "3. Existing ResumeConfigs:"
CONFIGS=$(curl -sf "${API_URL}/api/resume-configs" "${HEADERS[@]}" 2>&1 || true)
if echo "$CONFIGS" | grep -q '"success":true'; then
    echo "$CONFIGS" | python3 -c "
import sys, json
data = json.load(sys.stdin)
configs = data.get('data', [])
if not configs:
    print('   (none found)')
for c in configs:
    name = c.get('name', 'unnamed')
    cid = c.get('_id', '?')
    api_url = c.get('api_settings', {}).get('api_url', '(default)')
    template = c.get('google_drive_config', {}).get('template_id', '(none)')
    default = ' [DEFAULT]' if c.get('is_default') else ''
    print(f'   {name} ({cid}) api={api_url} template={template}{default}')
" 2>/dev/null || echo "   (could not parse response)"
else
    echo "   ⚠️  Could not fetch resume configs"
fi
echo ""

# ── Step 4: List existing PipelineConfigs ──────────────────────────────
echo "4. Existing PipelineConfigs:"
PIPELINE_CONFIGS=$(curl -sf "${API_URL}/api/pipeline/configs" "${HEADERS[@]}" 2>&1 || true)
if echo "$PIPELINE_CONFIGS" | grep -q '"success":true'; then
    echo "$PIPELINE_CONFIGS" | python3 -c "
import sys, json
data = json.load(sys.stdin)
configs = data.get('data', [])
if not configs:
    print('   (none found — you need to create at least one)')
for c in configs:
    name = c.get('name', 'unnamed')
    cid = c.get('_id', '?')
    enabled = c.get('enabled', False)
    auto = c.get('autoProcessOnScrapeComplete', False)
    rc = c.get('resumeConfigId', {})
    rc_name = rc.get('name', '?') if isinstance(rc, dict) else str(rc)
    sources = c.get('sourceFilters', {}).get('sources', [])
    print(f'   {name} ({cid}) enabled={enabled} auto={auto} resume_config={rc_name} sources={sources}')
" 2>/dev/null || echo "   (could not parse response)"
else
    echo "   ⚠️  Could not fetch pipeline configs"
fi
echo ""

# ── Step 5: Prompt to create PipelineConfig ────────────────────────────
echo "========================================"
echo " To create a new PipelineConfig, run:"
echo "========================================"
echo ""
echo "curl -X POST '${API_URL}/api/pipeline/configs' \\"
echo "  -H 'Content-Type: application/json' \\"
echo "  -H 'x-api-key: ${API_KEY}' \\"
echo "  -d '{"
echo "    \"name\": \"pm-remote-auto\","
echo "    \"description\": \"Auto-process pm-remote scrape runs\","
echo "    \"resumeConfigId\": \"<PASTE_RESUME_CONFIG_ID_HERE>\","
echo "    \"enabled\": true,"
echo "    \"autoProcessOnScrapeComplete\": true,"
echo "    \"mode\": \"async\","
echo "    \"sourceFilters\": {"
echo "      \"sources\": [\"hiring-cafe-pydoll-scraper\"]"
echo "    },"
echo "    \"processingSettings\": {"
echo "      \"model_name\": \"gpt-4o-mini\","
echo "      \"batch_size\": 20"
echo "    }"
echo "  }'"
echo ""
echo "========================================"
echo " To test the pipeline with a small scrape:"
echo "========================================"
echo ""
echo "curl -X POST 'https://job-scraper-production-2069.up.railway.app/scrape' \\"
echo "  -H 'Content-Type: application/json' \\"
echo "  -H 'x-api-key: <SCRAPER_API_KEY>' \\"
echo "  -d '{\"url\": \"https://hiring.cafe/?query=product+manager&workplaceType=remote\", \"config_name\": \"pm-remote\", \"max_jobs\": 3}'"
echo ""
