#!/usr/bin/env bash
# Loads the mock data into BigQuery and builds every table the LookML project uses.
#
#   PROJECT=my-gcp-project ./bigquery/run_pipeline.sh            # Gemini path (recommended)
#   PROJECT=my-gcp-project MODE=fallback ./bigquery/run_pipeline.sh   # no Vertex AI needed
#
# Optional: DATASET (voc_demo), LOCATION (EU), CONNECTION_ID (voc_vertex),
#           GEMINI_ENDPOINT, EMBEDDING_ENDPOINT, DATA_DIR
set -euo pipefail

: "${PROJECT:?Set PROJECT to your GCP project id}"
DATASET="${DATASET:-voc_demo}"
LOCATION="${LOCATION:-EU}"
MODE="${MODE:-ai}"
CONNECTION_ID="${CONNECTION_ID:-voc_vertex}"
GEMINI_ENDPOINT="${GEMINI_ENDPOINT:-gemini-2.5-flash}"
EMBEDDING_ENDPOINT="${EMBEDDING_ENDPOINT:-text-multilingual-embedding-002}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DATA_DIR="${DATA_DIR:-$ROOT/data}"
SQL_DIR="$ROOT/bigquery/sql"
SCHEMA_DIR="$ROOT/bigquery/schemas"
CONNECTION_LOCATION="$(echo "$LOCATION" | tr '[:upper:]' '[:lower:]')"

render() {
  sed -e "s|__PROJECT__|$PROJECT|g" \
      -e "s|__DATASET__|$DATASET|g" \
      -e "s|__CONNECTION_LOCATION__|$CONNECTION_LOCATION|g" \
      -e "s|__CONNECTION_ID__|$CONNECTION_ID|g" \
      -e "s|__GEMINI_ENDPOINT__|$GEMINI_ENDPOINT|g" \
      -e "s|__EMBEDDING_ENDPOINT__|$EMBEDDING_ENDPOINT|g" \
      "$SQL_DIR/$1"
}

run_sql() {
  echo "==> $1"
  render "$1" | bq --project_id="$PROJECT" --location="$LOCATION" query --use_legacy_sql=false --max_rows=50
}

scalar() {
  bq --project_id="$PROJECT" --location="$LOCATION" --format=csv query --use_legacy_sql=false "$1" | tail -n 1
}

load() {
  local table="$1" file="$2" schema="$3"
  echo "==> load $table <- $(basename "$file")"
  bq --project_id="$PROJECT" --location="$LOCATION" load --replace \
    --source_format=NEWLINE_DELIMITED_JSON "$PROJECT:$DATASET.$table" "$file" "$SCHEMA_DIR/$schema"
}

[[ -f "$DATA_DIR/transcripts.jsonl" ]] || python3 "$ROOT/generator/generate_mock_data.py" --out "$DATA_DIR"

echo "==> dataset $PROJECT:$DATASET ($LOCATION)"
bq --location="$LOCATION" mk -f --dataset \
  --description "Voice of the Customer demo (mock data)" "$PROJECT:$DATASET" >/dev/null

load raw_transcripts         "$DATA_DIR/transcripts.jsonl"         raw_transcripts.json
load raw_interaction_metrics "$DATA_DIR/interaction_metrics.jsonl" raw_interaction_metrics.json
load eval_ground_truth       "$DATA_DIR/ground_truth.jsonl"        eval_ground_truth.json

if [[ "$MODE" == "ai" ]]; then
  echo "==> Vertex AI connection $CONNECTION_LOCATION.$CONNECTION_ID"
  bq mk --connection --project_id="$PROJECT" --location="$LOCATION" \
    --connection_type=CLOUD_RESOURCE "$CONNECTION_ID" 2>/dev/null || true
  SA="$(bq show --format=json --connection "$PROJECT.$CONNECTION_LOCATION.$CONNECTION_ID" \
        | python3 -c 'import json,sys; print(json.load(sys.stdin)["cloudResource"]["serviceAccountId"])')"
  gcloud projects add-iam-policy-binding "$PROJECT" --member="serviceAccount:$SA" \
    --role="roles/aiplatform.user" --condition=None --quiet >/dev/null
  echo "    granted roles/aiplatform.user to $SA (waiting 60s for IAM propagation)"
  sleep 60

  run_sql 10_models.sql
  # Drop fallback rows (if the fallback was loaded earlier) so Gemini re-enriches them; real insights are kept.
  bq --project_id="$PROJECT" --location="$LOCATION" query --use_legacy_sql=false \
    "DELETE FROM \`$PROJECT.$DATASET.conversation_insights\` WHERE model_version = 'fallback-ground-truth'" >/dev/null 2>&1 || true
  for attempt in 1 2 3 4; do
    run_sql 20_enrich_conversations.sql
    missing="$(scalar "SELECT COUNT(*) FROM \`$PROJECT.$DATASET.raw_transcripts\` t
      JOIN (SELECT conversation_id, ANY_VALUE(queue_name) q FROM \`$PROJECT.$DATASET.raw_interaction_metrics\` GROUP BY 1) m USING (conversation_id)
      WHERE m.q != 'B2C_Reklamation'
        AND t.conversation_id NOT IN (SELECT conversation_id FROM \`$PROJECT.$DATASET.conversation_insights\`)")"
    echo "    conversations still missing insights: $missing"
    [[ "$missing" -lt 20 ]] && break
  done
  run_sql 30_discover_topics.sql
  run_sql 40_build_marts.sql
  run_sql 50_topic_recommendations.sql
  run_sql 60_evaluate_against_ground_truth.sql
else
  load conversation_insights          "$DATA_DIR/fallback_conversation_insights.jsonl" conversation_insights.json
  load fallback_topic_catalog         "$DATA_DIR/fallback_topic_catalog.jsonl"         fallback_topic_catalog.json
  load fallback_topic_recommendations "$DATA_DIR/fallback_topic_recommendations.jsonl" fallback_topic_recommendations.json
  run_sql 31_topics_from_fallback.sql
  run_sql 40_build_marts.sql
  run_sql 51_recommendations_from_fallback.sql
fi

echo "==> done. Tables in $PROJECT:$DATASET:"
bq --project_id="$PROJECT" ls "$DATASET"
