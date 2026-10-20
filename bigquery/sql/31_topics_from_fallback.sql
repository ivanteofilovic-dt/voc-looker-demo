-- Fallback path (no Vertex AI): builds the same topic tables from the pre-labelled
-- fallback insights, so the LookML and dashboards work unchanged.

CREATE OR REPLACE TABLE `__PROJECT__.__DATASET__.issue_mentions` AS
SELECT conversation_id, LOWER(TRIM(primary_issue)) AS issue_label, TRUE AS is_primary
FROM `__PROJECT__.__DATASET__.conversation_insights`
WHERE primary_issue IS NOT NULL
UNION ALL
SELECT conversation_id, LOWER(TRIM(s)), FALSE
FROM `__PROJECT__.__DATASET__.conversation_insights`, UNNEST(secondary_issues) AS s
WHERE s IS NOT NULL;

CREATE OR REPLACE TABLE `__PROJECT__.__DATASET__.topic_catalog` AS
SELECT
  FORMAT('T%02d', ROW_NUMBER() OVER (ORDER BY f.topic_name)) AS topic_id,
  CONCAT(UPPER(SUBSTR(f.topic_name, 1, 1)), SUBSTR(f.topic_name, 2)) AS topic_name,
  f.theme,
  f.description,
  (SELECT COUNT(*) FROM `__PROJECT__.__DATASET__.issue_mentions` AS im WHERE im.issue_label = f.topic_name) AS mentions_at_creation,
  'fallback-v1' AS taxonomy_version,
  CURRENT_TIMESTAMP() AS created_at
FROM `__PROJECT__.__DATASET__.fallback_topic_catalog` AS f;

CREATE OR REPLACE TABLE `__PROJECT__.__DATASET__.conversation_topics` AS
SELECT
  im.conversation_id,
  t.topic_id,
  t.topic_name,
  t.theme,
  LOGICAL_OR(im.is_primary) AS is_primary,
  ANY_VALUE(im.issue_label) AS issue_label
FROM `__PROJECT__.__DATASET__.issue_mentions` AS im
JOIN `__PROJECT__.__DATASET__.topic_catalog` AS t ON LOWER(t.topic_name) = im.issue_label
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
SELECT CURRENT_TIMESTAMP(), 'fallback-v1', 'fallback_load', COUNT(*),
       STRING_AGG(topic_name, '; ' ORDER BY topic_name), SESSION_USER()
FROM `__PROJECT__.__DATASET__.topic_catalog`;
