-- Data-driven topic discovery (no predefined categories):
--   1. every free-text issue label Gemini extracted (primary + secondary = multi-intent)
--   2. multilingual embeddings of each distinct label
--   3. k-means clustering of the embeddings
--   4. Gemini names each cluster -> topic catalog (level 2) and assigns a theme (level 1)
--   5. conversations are mapped to topics, and the change is written to an audit log.
-- In production this runs weekly; daily runs assign new labels to the nearest existing
-- topic and only open a "new topic candidate" when no centroid is close enough.

DECLARE taxonomy_version STRING DEFAULT FORMAT_TIMESTAMP('v%Y%m%d-%H%M', CURRENT_TIMESTAMP());
DECLARE naming_prompt STRING DEFAULT """
You maintain the customer-contact taxonomy for a Swedish telecom operator.
The issue labels below were extracted from customer conversations and grouped together because they are semantically similar.
The number in brackets shows how often each label occurs.

Return:
- topic_name: a specific, business-friendly name for what this group of contacts is about (max 7 words, English, sentence case).
  Keep concrete details such as product, device, event or partner (e.g. "Wi-Fi drops after router firmware update" rather than "Internet problems").
- theme: a broad level-1 area. Prefer one of: Billing & pricing, Orders & delivery, Onboarding & porting, Technical support – Mobile,
  Technical support – Fixed, Digital self-service, Retention & churn, Sales & upgrades, TV. If none fits, propose a new short theme.
- description: one sentence describing which contacts belong to this topic.
If the group mixes several unrelated issues, name it after the most frequent one.
""";

CREATE OR REPLACE TABLE `__PROJECT__.__DATASET__.issue_mentions` AS
SELECT conversation_id, LOWER(TRIM(primary_issue)) AS issue_label, TRUE AS is_primary
FROM `__PROJECT__.__DATASET__.conversation_insights`
WHERE primary_issue IS NOT NULL
UNION ALL
SELECT conversation_id, LOWER(TRIM(s)) AS issue_label, FALSE AS is_primary
FROM `__PROJECT__.__DATASET__.conversation_insights`, UNNEST(secondary_issues) AS s
WHERE s IS NOT NULL;

CREATE OR REPLACE TABLE `__PROJECT__.__DATASET__.issue_label_embeddings` AS
SELECT content AS issue_label, ml_generate_embedding_result AS embedding
FROM ML.GENERATE_EMBEDDING(
  MODEL `__PROJECT__.__DATASET__.embedding_model`,
  (SELECT DISTINCT issue_label AS content FROM `__PROJECT__.__DATASET__.issue_mentions`),
  STRUCT(TRUE AS flatten_json_output, 'CLUSTERING' AS task_type)
)
WHERE ml_generate_embedding_status = '';

-- num_clusters is the main tuning knob: too low merges topics, too high splits them.
-- Clusters that get the same name from Gemini are merged below, so erring high is safer.
CREATE OR REPLACE MODEL `__PROJECT__.__DATASET__.issue_topic_kmeans`
OPTIONS (
  model_type = 'KMEANS',
  num_clusters = 20,
  kmeans_init_method = 'KMEANS++',
  distance_type = 'COSINE',
  standardize_features = FALSE
) AS
SELECT embedding FROM `__PROJECT__.__DATASET__.issue_label_embeddings`;

CREATE OR REPLACE TABLE `__PROJECT__.__DATASET__.issue_label_clusters` AS
SELECT issue_label, centroid_id AS cluster_id
FROM ML.PREDICT(
  MODEL `__PROJECT__.__DATASET__.issue_topic_kmeans`,
  (SELECT issue_label, embedding FROM `__PROJECT__.__DATASET__.issue_label_embeddings`)
);

CREATE OR REPLACE TABLE `__PROJECT__.__DATASET__.cluster_names` AS
WITH label_counts AS (
  SELECT issue_label, COUNT(*) AS mentions
  FROM `__PROJECT__.__DATASET__.issue_mentions`
  GROUP BY issue_label
),
cluster_input AS (
  SELECT
    c.cluster_id,
    SUM(l.mentions) AS mentions,
    STRING_AGG(FORMAT('- %s (%d)', c.issue_label, l.mentions), '\n' ORDER BY l.mentions DESC LIMIT 40) AS sample_labels
  FROM `__PROJECT__.__DATASET__.issue_label_clusters` AS c
  JOIN label_counts AS l USING (issue_label)
  GROUP BY c.cluster_id
)
SELECT cluster_id, mentions, topic_name, theme, description
FROM AI.GENERATE_TABLE(
  MODEL `__PROJECT__.__DATASET__.gemini_model`,
  (
    SELECT cluster_id, mentions, CONCAT(naming_prompt, '\n\nISSUE LABELS (count):\n', sample_labels) AS prompt
    FROM cluster_input
  ),
  STRUCT('topic_name STRING, theme STRING, description STRING' AS output_schema, 0.0 AS temperature)
)
WHERE status = '';

CREATE OR REPLACE TABLE `__PROJECT__.__DATASET__.cluster_topic_map` AS
SELECT
  cluster_id,
  FORMAT('T%02d', MIN(cluster_id) OVER (PARTITION BY LOWER(TRIM(topic_name)))) AS topic_id
FROM `__PROJECT__.__DATASET__.cluster_names`;

CREATE OR REPLACE TABLE `__PROJECT__.__DATASET__.topic_catalog` AS
SELECT
  m.topic_id,
  ARRAY_AGG(n.topic_name ORDER BY n.mentions DESC LIMIT 1)[OFFSET(0)] AS topic_name,
  ARRAY_AGG(n.theme ORDER BY n.mentions DESC LIMIT 1)[OFFSET(0)] AS theme,
  ARRAY_AGG(n.description ORDER BY n.mentions DESC LIMIT 1)[OFFSET(0)] AS description,
  SUM(n.mentions) AS mentions_at_creation,
  taxonomy_version,
  CURRENT_TIMESTAMP() AS created_at
FROM `__PROJECT__.__DATASET__.cluster_topic_map` AS m
JOIN `__PROJECT__.__DATASET__.cluster_names` AS n USING (cluster_id)
GROUP BY m.topic_id;

CREATE OR REPLACE TABLE `__PROJECT__.__DATASET__.conversation_topics` AS
SELECT
  im.conversation_id,
  t.topic_id,
  t.topic_name,
  t.theme,
  LOGICAL_OR(im.is_primary) AS is_primary,
  ARRAY_AGG(im.issue_label ORDER BY im.is_primary DESC LIMIT 1)[OFFSET(0)] AS issue_label
FROM `__PROJECT__.__DATASET__.issue_mentions` AS im
JOIN `__PROJECT__.__DATASET__.issue_label_clusters` AS c USING (issue_label)
JOIN `__PROJECT__.__DATASET__.cluster_topic_map` AS ctm USING (cluster_id)
JOIN `__PROJECT__.__DATASET__.topic_catalog` AS t USING (topic_id)
GROUP BY im.conversation_id, t.topic_id, t.topic_name, t.theme;

CREATE TABLE IF NOT EXISTS `__PROJECT__.__DATASET__.taxonomy_change_log` (
  changed_at TIMESTAMP,
  taxonomy_version STRING,
  change_type STRING,
  topic_count INT64,
  details STRING,
  changed_by STRING
);

INSERT INTO `__PROJECT__.__DATASET__.taxonomy_change_log`
SELECT CURRENT_TIMESTAMP(), taxonomy_version, 'full_rediscovery', COUNT(*),
       STRING_AGG(topic_name, '; ' ORDER BY topic_name), SESSION_USER()
FROM `__PROJECT__.__DATASET__.topic_catalog`;

SELECT topic_id, topic_name, theme, mentions_at_creation
FROM `__PROJECT__.__DATASET__.topic_catalog`
ORDER BY mentions_at_creation DESC;
