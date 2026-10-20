-- Gemini turns each topic's aggregated evidence into a problem statement, a recommended
-- action and a suggested owner, plus one "Insight of the day" for the start page.
-- Only aggregated, non-identifying statistics are sent to the model.

DECLARE rec_prompt STRING DEFAULT """
You are a Voice-of-the-Customer advisor for a Swedish telecom operator.
Based ONLY on the aggregated facts below about one customer-contact topic, return:
- problem_statement: one sentence, written as a standardised problem statement (what breaks, for whom, with what effect).
- recommended_action: 1-2 concrete improvement actions that would remove or reduce the contacts (prefer fixing the root cause over deflecting).
- suggested_owner: the most likely owning function (e.g. "Billing – Invoice Experience", "Fixed Broadband – CPE & Network Operations").
- expected_impact: one sentence on the expected impact, referring to the numbers provided. Do not invent numbers.
If the topic is value demand (sales, upgrades) recommend how to strengthen it rather than reduce it.
""";

DECLARE iotd_prompt STRING DEFAULT """
Write the "Insight of the day" for a Voice-of-the-Customer start page, for business users.
Use only the facts provided. Return:
- headline: max 12 words.
- explanation: 2-3 plain-language sentences that quote the numbers given and say why it matters.
""";

CREATE OR REPLACE TABLE `__PROJECT__.__DATASET__.topic_recommendations` AS
WITH base AS (
  SELECT ct.topic_id, ct.topic_name, f.* EXCEPT (primary_topic, primary_theme, primary_topic_id)
  FROM `__PROJECT__.__DATASET__.conversation_topics` AS ct
  JOIN `__PROJECT__.__DATASET__.conversation_facts` AS f ON f.conversation_id = ct.conversation_id
),
stats AS (
  SELECT
    topic_id,
    ANY_VALUE(topic_name) AS topic_name,
    COUNT(DISTINCT conversation_id) AS contacts,
    COUNT(DISTINCT customer_key) AS customers,
    ROUND(AVG(aht_sec) / 60, 1) AS avg_aht_min,
    ROUND(AVG(csat_score), 2) AS avg_csat,
    ROUND(100 * AVG(IF(followed_by_repeat_7d, 1, 0))) AS repeat_pct,
    ROUND(100 * AVG(IF(churned_within_30d, 1, 0))) AS churn_pct,
    ROUND(100 * AVG(IF(failure_demand, 1, 0))) AS failure_demand_pct,
    ROUND(100 * AVG(IF(self_service_attempted, 1, 0))) AS self_service_pct
  FROM base
  GROUP BY topic_id
),
top_values AS (
  SELECT topic_id, kind, STRING_AGG(FORMAT('%s (%d)', val, n), '; ' ORDER BY n DESC LIMIT 6) AS top_list
  FROM (
    SELECT topic_id, 'root_cause' AS kind, root_cause AS val, COUNT(*) AS n FROM base WHERE root_cause IS NOT NULL GROUP BY 1, 2, 3
    UNION ALL
    SELECT topic_id, 'trigger', trigger_event, COUNT(*) FROM base WHERE trigger_event IS NOT NULL GROUP BY 1, 2, 3
    UNION ALL
    SELECT topic_id, 'resolution', resolution, COUNT(*) FROM base WHERE resolution IS NOT NULL GROUP BY 1, 2, 3
    UNION ALL
    SELECT topic_id, 'segment', CONCAT(line_of_business, ' / ', tenure_band), COUNT(*) FROM base GROUP BY 1, 2, 3
  )
  GROUP BY topic_id, kind
),
prompts AS (
  SELECT
    s.topic_id,
    s.topic_name,
    FORMAT("""%s

TOPIC: %s
Contacts: %d | Unique customers: %d | Avg handle time: %t min | Avg CSAT (1-5): %t
Repeat contact within 7 days: %t%% | Churn within 30 days: %t%% | Failure demand: %t%% | Tried self-service first: %t%%
Top root causes: %s
Top triggers before contact: %s
Typical resolutions: %s
Main segments (line of business / tenure): %s""",
      rec_prompt, s.topic_name, s.contacts, s.customers, s.avg_aht_min, s.avg_csat,
      s.repeat_pct, s.churn_pct, s.failure_demand_pct, s.self_service_pct,
      IFNULL(rc.top_list, 'n/a'), IFNULL(tr.top_list, 'n/a'), IFNULL(rs.top_list, 'n/a'), IFNULL(sg.top_list, 'n/a')) AS prompt
  FROM stats AS s
  LEFT JOIN top_values AS rc ON rc.topic_id = s.topic_id AND rc.kind = 'root_cause'
  LEFT JOIN top_values AS tr ON tr.topic_id = s.topic_id AND tr.kind = 'trigger'
  LEFT JOIN top_values AS rs ON rs.topic_id = s.topic_id AND rs.kind = 'resolution'
  LEFT JOIN top_values AS sg ON sg.topic_id = s.topic_id AND sg.kind = 'segment'
  WHERE s.contacts >= 10
)
SELECT
  topic_id, topic_name, problem_statement, recommended_action, suggested_owner, expected_impact,
  '__GEMINI_ENDPOINT__' AS model_version, CURRENT_TIMESTAMP() AS generated_at
FROM AI.GENERATE_TABLE(
  MODEL `__PROJECT__.__DATASET__.gemini_model`,
  (SELECT topic_id, topic_name, prompt FROM prompts),
  STRUCT('problem_statement STRING, recommended_action STRING, suggested_owner STRING, expected_impact STRING' AS output_schema,
         0.0 AS temperature)
)
WHERE status = '';

CREATE OR REPLACE TABLE `__PROJECT__.__DATASET__.insight_of_the_day` AS
WITH pick AS (
  SELECT w.*, SAFE_DIVIDE(w.contacts_last_7d, NULLIF(w.prior_weekly_avg, 0)) AS growth_ratio
  FROM `__PROJECT__.__DATASET__.topic_weekly_trend` AS w
  WHERE w.contacts_last_7d >= 15
  ORDER BY IFNULL(SAFE_DIVIDE(w.contacts_last_7d, NULLIF(w.prior_weekly_avg, 0)), 99) DESC, w.contacts_last_7d DESC
  LIMIT 1
)
SELECT
  as_of_date, topic_id, topic_name, contacts_last_7d, prior_weekly_avg, growth_ratio,
  headline, explanation, CURRENT_TIMESTAMP() AS generated_at
FROM AI.GENERATE_TABLE(
  MODEL `__PROJECT__.__DATASET__.gemini_model`,
  (
    SELECT p.*, FORMAT("""%s

Topic: %s
Contacts last 7 days: %d
Average contacts per week in the 4 weeks before: %t
First seen in the data: %t
Problem statement: %s
Recommended action: %s""",
      iotd_prompt, p.topic_name, p.contacts_last_7d, ROUND(p.prior_weekly_avg, 1), p.first_seen_date,
      IFNULL(r.problem_statement, 'n/a'), IFNULL(r.recommended_action, 'n/a')) AS prompt
    FROM pick AS p
    LEFT JOIN `__PROJECT__.__DATASET__.topic_recommendations` AS r USING (topic_id)
  ),
  STRUCT('headline STRING, explanation STRING' AS output_schema, 0.0 AS temperature)
)
WHERE status = '';
