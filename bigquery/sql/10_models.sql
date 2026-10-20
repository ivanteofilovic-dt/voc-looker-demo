-- Remote models on Vertex AI, called from BigQuery SQL through a Cloud resource connection.
-- Placeholders (__PROJECT__ etc.) are substituted by run_pipeline.sh.

CREATE OR REPLACE MODEL `__PROJECT__.__DATASET__.gemini_model`
  REMOTE WITH CONNECTION `__PROJECT__.__CONNECTION_LOCATION__.__CONNECTION_ID__`
  OPTIONS (ENDPOINT = '__GEMINI_ENDPOINT__');

-- Multilingual embeddings so Swedish and English labels land in the same vector space.
CREATE OR REPLACE MODEL `__PROJECT__.__DATASET__.embedding_model`
  REMOTE WITH CONNECTION `__PROJECT__.__CONNECTION_LOCATION__.__CONNECTION_ID__`
  OPTIONS (ENDPOINT = '__EMBEDDING_ENDPOINT__');
