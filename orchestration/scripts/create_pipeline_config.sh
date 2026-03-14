#!/usr/bin/env bash
#
# Create a PipelineConfig linked to a ResumeConfig.
#
# Usage:
#   export DEJDASH_API_URL="https://your-dejdash-backend.up.railway.app"
#   export DEJDASH_API_KEY="your-api-key"
#   ./create_pipeline_config.sh <resume_config_id> [name] [source_filter]
#
# Examples:
#   ./create_pipeline_config.sh 665a1234abcd5678ef901234
#   ./create_pipeline_config.sh 665a1234abcd5678ef901234 pm-remote-auto
#   ./create_pipeline_config.sh 665a1234abcd5678ef901234 pm-remote-auto hiring-cafe-pydoll-scraper
#
set -euo pipefail

API_URL="${DEJDASH_API_URL:?Set DEJDASH_API_URL}"
API_KEY="${DEJDASH_API_KEY:?Set DEJDASH_API_KEY}"

RESUME_CONFIG_ID="${1:?Usage: $0 <resume_config_id> [name] [source_filter]}"
NAME="${2:-auto-$(echo "$RESUME_CONFIG_ID" | tail -c 7)}"
SOURCE_FILTER="${3:-}"

SOURCES_JSON="[]"
if [ -n "$SOURCE_FILTER" ]; then
    SOURCES_JSON="[\"${SOURCE_FILTER}\"]"
fi

echo "Creating PipelineConfig '${NAME}'..."
echo "  resumeConfigId: ${RESUME_CONFIG_ID}"
echo "  sourceFilters:  ${SOURCES_JSON}"
echo ""

RESPONSE=$(curl -sf -X POST "${API_URL}/api/pipeline/configs" \
    -H "Content-Type: application/json" \
    -H "x-api-key: ${API_KEY}" \
    -d "{
        \"name\": \"${NAME}\",
        \"description\": \"Auto-pipeline for ${NAME}\",
        \"resumeConfigId\": \"${RESUME_CONFIG_ID}\",
        \"enabled\": true,
        \"autoProcessOnScrapeComplete\": true,
        \"mode\": \"async\",
        \"sourceFilters\": {
            \"sources\": ${SOURCES_JSON}
        },
        \"processingSettings\": {
            \"model_name\": \"gpt-4o-mini\",
            \"batch_size\": 20
        }
    }" 2>&1)

if echo "$RESPONSE" | grep -q '"success":true'; then
    CONFIG_ID=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['_id'])" 2>/dev/null || echo "?")
    echo "✅ Created PipelineConfig: ${CONFIG_ID}"
    echo ""
    echo "$RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$RESPONSE"
else
    echo "❌ Failed to create PipelineConfig"
    echo "$RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$RESPONSE"
    exit 1
fi
