-- Fallback path (no Vertex AI): recommendations from the pre-written file and a templated insight of the day.

CREATE OR REPLACE TABLE `__PROJECT__.__DATASET__.topic_recommendations` AS
SELECT
  t.topic_id, t.topic_name, f.problem_statement, f.recommended_action, f.suggested_owner, f.expected_impact,
  'fallback' AS model_version, CURRENT_TIMESTAMP() AS generated_at
FROM `__PROJECT__.__DATASET__.topic_catalog` AS t
JOIN `__PROJECT__.__DATASET__.fallback_topic_recommendations` AS f ON LOWER(t.topic_name) = f.topic_name;

CREATE OR REPLACE TABLE `__PROJECT__.__DATASET__.insight_of_the_day` AS
WITH pick AS (
  SELECT w.*, SAFE_DIVIDE(w.contacts_last_7d, NULLIF(w.prior_weekly_avg, 0)) AS growth_ratio
  FROM `__PROJECT__.__DATASET__.topic_weekly_trend` AS w
  WHERE w.contacts_last_7d >= 15
  ORDER BY IFNULL(SAFE_DIVIDE(w.contacts_last_7d, NULLIF(w.prior_weekly_avg, 0)), 99) DESC, w.contacts_last_7d DESC
  LIMIT 1
)
SELECT
  p.as_of_date, p.topic_id, p.topic_name, p.contacts_last_7d, p.prior_weekly_avg, p.growth_ratio,
  FORMAT('%s: %d contacts in 7 days', p.topic_name, p.contacts_last_7d) AS headline,
  FORMAT('Up from about %.0f per week in the previous four weeks. %s', IFNULL(p.prior_weekly_avg, 0), IFNULL(r.problem_statement, '')) AS explanation,
  CURRENT_TIMESTAMP() AS generated_at
FROM pick AS p
LEFT JOIN `__PROJECT__.__DATASET__.topic_recommendations` AS r USING (topic_id);
