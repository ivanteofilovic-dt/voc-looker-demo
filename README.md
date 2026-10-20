# Voice of the Customer on Google Cloud – Looker demo kit

| Path | What it is |
|---|---|
| `docs/architecture.md` | Production architecture proposal (GCP + Looker), mapped to the requirements document and the 8 follow-up questions |
| `docs/demo-script.md` | Tomorrow's demo: prep checklist, storyline, act-by-act click path, agent prompts, fallback plan |
| `generator/generate_mock_data.py` | Mock data generator: PII-redacted transcripts (EN/SV) + Genesys-style operational metrics, with planted storylines |
| `data/` | Generated files (`transcripts.jsonl`, `interaction_metrics.jsonl/.csv`, ground truth, fallback insights) |
| `bigquery/run_pipeline.sh` | Loads data and builds all tables (Gemini path or `MODE=fallback`) |
| `bigquery/sql/` | Gemini extraction, topic discovery, marts, recommendations, evaluation |
| `looker/` | LookML project: model, views, two dashboards, Conversational Analytics agent instructions |

## Quick start

```bash
# 1. (optional) regenerate the mock data – storylines are placed relative to --end
python3 generator/generate_mock_data.py --end 2026-10-20

# 2. build BigQuery tables with Gemini (BigQuery + Vertex AI APIs enabled)
PROJECT=my-gcp-project ./bigquery/run_pipeline.sh

#    ...or without Vertex AI, from pre-labelled fallback data
PROJECT=my-gcp-project DATASET=voc_demo_fallback MODE=fallback ./bigquery/run_pipeline.sh

# 3. copy looker/ into a LookML project, set the constants in manifest.lkml, validate, deploy
```

Optional variables for the pipeline: `LOCATION` (default `EU`), `CONNECTION_ID` (`voc_vertex`),
`GEMINI_ENDPOINT` (`gemini-2.5-flash`; use the newest GA Flash model in your region), `EMBEDDING_ENDPOINT`
(`text-multilingual-embedding-002`).
