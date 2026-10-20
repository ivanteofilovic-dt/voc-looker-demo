project_name: "voc_demo"

# Adjust these four values to your environment before validating the project.
constant: CONNECTION_NAME {
  value: "voc_bigquery"
}

constant: GCP_PROJECT {
  value: "your-gcp-project"
}

constant: DATASET {
  value: "voc_demo"
}

# Only used by the optional "Ask the transcripts" explore (BigQuery AI.IF at query time).
constant: VERTEX_CONNECTION {
  value: "your-gcp-project.eu.voc_vertex"
}

# Cost proxy for handled time (SEK per handled minute). Governed centrally, used in all cost measures.
constant: COST_PER_HANDLED_MINUTE_SEK {
  value: "9"
}
