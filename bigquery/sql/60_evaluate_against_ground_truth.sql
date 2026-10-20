-- Model quality check against the generator's ground truth (requirement area 14: repeatable,
-- comparable evaluation across prompt/model versions). Results are appended to eval_runs.

CREATE OR REPLACE TABLE `__PROJECT__.__DATASET__.eval_topic_purity` AS
WITH j AS (
  SELECT f.primary_topic, g.gt_topic
  FROM `__PROJECT__.__DATASET__.conversation_facts` AS f
  JOIN `__PROJECT__.__DATASET__.eval_ground_truth` AS g USING (conversation_id)
  WHERE f.primary_topic IS NOT NULL
),
per_topic AS (
  SELECT primary_topic, gt_topic, COUNT(*) AS n FROM j GROUP BY 1, 2
)
SELECT
  primary_topic AS discovered_topic,
  ARRAY_AGG(STRUCT(gt_topic, n) ORDER BY n DESC LIMIT 1)[OFFSET(0)].gt_topic AS dominant_true_topic,
  SUM(n) AS conversations,
  ROUND(MAX(n) / SUM(n), 3) AS purity
FROM per_topic
GROUP BY primary_topic;

CREATE TABLE IF NOT EXISTS `__PROJECT__.__DATASET__.eval_runs` (
  run_at TIMESTAMP, model_version STRING, prompt_version STRING, metric STRING, value FLOAT64, n INT64
);

INSERT INTO `__PROJECT__.__DATASET__.eval_runs`
WITH j AS (
  SELECT f.*, g.* EXCEPT (conversation_id, hardware_model, network_operator),
         g.hardware_model AS gt_hardware, g.network_operator AS gt_network
  FROM `__PROJECT__.__DATASET__.conversation_facts` AS f
  JOIN `__PROJECT__.__DATASET__.eval_ground_truth` AS g ON g.conversation_id = f.conversation_id
  WHERE f.classification_status = 'Classified'
),
v AS (SELECT ANY_VALUE(model_version) AS mv, ANY_VALUE(prompt_version) AS pv FROM j)
SELECT CURRENT_TIMESTAMP(), v.mv, v.pv, metric, value, n FROM v, (
  SELECT 'topic_purity_weighted' AS metric,
         SAFE_DIVIDE(SUM(purity * conversations), SUM(conversations)) AS value, CAST(SUM(conversations) AS INT64) AS n
  FROM `__PROJECT__.__DATASET__.eval_topic_purity`
  UNION ALL
  SELECT 'resolved_accuracy', AVG(IF(resolved_in_contact = resolved, 1, 0)), COUNT(*) FROM j
  UNION ALL
  SELECT 'self_service_accuracy', AVG(IF(self_service_attempted = self_service, 1, 0)), COUNT(*) FROM j
  UNION ALL
  SELECT 'competitor_recall', AVG(IF(competitor_name IS NOT NULL, 1, 0)), COUNT(*) FROM j WHERE competitor IS NOT NULL
  UNION ALL
  SELECT 'competitor_precision', AVG(IF(LOWER(competitor_name) = LOWER(competitor), 1, 0)), COUNT(*) FROM j WHERE competitor_name IS NOT NULL
  UNION ALL
  SELECT 'hardware_recall', AVG(IF(hardware_model IS NOT NULL, 1, 0)), COUNT(*) FROM j WHERE gt_hardware IS NOT NULL
  UNION ALL
  SELECT 'multi_intent_recall', AVG(IF(topic_count > 1, 1, 0)), COUNT(*) FROM j WHERE gt_secondary_topic IS NOT NULL
);

SELECT * FROM `__PROJECT__.__DATASET__.eval_topic_purity` ORDER BY conversations DESC;
