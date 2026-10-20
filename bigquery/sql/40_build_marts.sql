-- Curated marts consumed by Looker.
--   conversation_facts : one row per conversation = operational metrics + AI insights + topic + journey flags
--   topic_weekly_trend : last-7-days vs previous-4-weeks per topic (used for "insight of the day")
--   data_freshness     : last load / last event / duplicates / late arrivals per source

CREATE OR REPLACE TABLE `__PROJECT__.__DATASET__.conversation_facts`
PARTITION BY DATE(started_at)
CLUSTER BY line_of_business, business_type, channel
AS
WITH metrics AS (
  -- Duplicate deliveries keep the latest version; late-arriving rows are included on every rebuild.
  SELECT *
  FROM `__PROJECT__.__DATASET__.raw_interaction_metrics`
  QUALIFY ROW_NUMBER() OVER (PARTITION BY conversation_id ORDER BY ingested_at DESC) = 1
),
transcripts AS (
  SELECT conversation_id, turn_count
  FROM `__PROJECT__.__DATASET__.raw_transcripts`
  QUALIFY ROW_NUMBER() OVER (PARTITION BY conversation_id ORDER BY ingested_at DESC) = 1
),
primary_topic AS (
  SELECT conversation_id, topic_id, topic_name, theme
  FROM `__PROJECT__.__DATASET__.conversation_topics`
  WHERE is_primary
  QUALIFY ROW_NUMBER() OVER (PARTITION BY conversation_id ORDER BY topic_id) = 1
),
topic_counts AS (
  SELECT conversation_id, COUNT(*) AS topic_count
  FROM `__PROJECT__.__DATASET__.conversation_topics`
  GROUP BY conversation_id
),
joined AS (
  SELECT
    m.conversation_id,
    m.customer_key,
    m.started_at,
    m.ended_at,
    m.channel,
    m.contact_type,
    m.queue_name,
    m.business_type,
    m.line_of_business,
    m.region,
    m.tenure_months,
    m.language,
    m.handled_by,
    m.voicebot_attempted,
    m.asa_sec,
    m.talk_sec,
    m.hold_sec,
    m.mute_sec,
    m.acw_sec,
    m.aht_sec,
    m.transferred,
    m.csat_score,
    m.churned_within_30d,
    m.ingested_at,
    t.conversation_id IS NOT NULL AS has_transcript,
    CASE
      WHEN m.queue_name IN ('B2C_Reklamation') THEN 'Excluded (privacy rule)'
      WHEN t.conversation_id IS NULL THEN 'No transcript captured'
      WHEN i.conversation_id IS NULL THEN 'Pending enrichment'
      ELSE 'Classified'
    END AS classification_status,
    pt.topic_id AS primary_topic_id,
    pt.topic_name AS primary_topic,
    pt.theme AS primary_theme,
    IFNULL(tc.topic_count, 0) AS topic_count,
    i.summary,
    i.primary_issue,
    ARRAY_TO_STRING(i.secondary_issues, '; ') AS secondary_issues,
    i.journey_step,
    i.product_area,
    i.hardware_model,
    i.network_operator,
    i.customer_sentiment,
    i.sentiment_score,
    i.trigger_event,
    i.root_cause,
    i.resolution,
    i.resolved_in_contact,
    i.failure_demand,
    i.self_service_attempted,
    i.repeat_contact_mentioned,
    i.churn_risk,
    i.termination_requested,
    i.competitor_name,
    i.competitor_offer,
    NULLIF(i.competitor_price_sek, 0) AS competitor_price_sek,
    i.evidence_quote,
    i.confidence,
    i.model_version,
    i.prompt_version
  FROM metrics AS m
  LEFT JOIN transcripts AS t ON t.conversation_id = m.conversation_id
  LEFT JOIN `__PROJECT__.__DATASET__.conversation_insights` AS i ON i.conversation_id = m.conversation_id
  LEFT JOIN primary_topic AS pt ON pt.conversation_id = m.conversation_id
  LEFT JOIN topic_counts AS tc ON tc.conversation_id = m.conversation_id
)
SELECT
  *,
  CASE
    WHEN tenure_months < 3 THEN '0-90 days'
    WHEN tenure_months < 12 THEN '3-12 months'
    WHEN tenure_months < 24 THEN '1-2 years'
    WHEN tenure_months < 60 THEN '2-5 years'
    WHEN tenure_months < 120 THEN '5-10 years'
    ELSE '10+ years'
  END AS tenure_band,
  CASE
    WHEN tenure_months < 3 THEN 1
    WHEN tenure_months < 12 THEN 2
    WHEN tenure_months < 24 THEN 3
    WHEN tenure_months < 60 THEN 4
    WHEN tenure_months < 120 THEN 5
    ELSE 6
  END AS tenure_band_sort,
  -- Journey stitching on the pseudonymised customer key: works across channels and without product context.
  IFNULL(TIMESTAMP_DIFF(started_at, LAG(started_at) OVER by_customer, HOUR) <= 168, FALSE) AS is_repeat_contact,
  LAG(channel) OVER by_customer AS previous_contact_channel,
  IFNULL(TIMESTAMP_DIFF(LEAD(started_at) OVER by_customer, started_at, HOUR) <= 168, FALSE) AS followed_by_repeat_7d,
  IFNULL(TIMESTAMP_DIFF(LEAD(started_at) OVER by_customer_topic, started_at, HOUR) <= 168, FALSE) AS followed_by_same_topic_repeat_7d,
  ROW_NUMBER() OVER by_customer AS customer_contact_seq
FROM joined
WINDOW
  by_customer AS (PARTITION BY customer_key ORDER BY started_at),
  by_customer_topic AS (PARTITION BY customer_key, primary_topic_id ORDER BY started_at);

CREATE OR REPLACE TABLE `__PROJECT__.__DATASET__.topic_weekly_trend` AS
WITH daily AS (
  SELECT DATE(f.started_at, 'Europe/Stockholm') AS d, ct.topic_id, ANY_VALUE(ct.topic_name) AS topic_name,
         COUNT(DISTINCT f.conversation_id) AS contacts
  FROM `__PROJECT__.__DATASET__.conversation_topics` AS ct
  JOIN `__PROJECT__.__DATASET__.conversation_facts` AS f USING (conversation_id)
  GROUP BY 1, 2
),
bounds AS (SELECT MAX(d) AS max_d FROM daily)
SELECT
  topic_id,
  ANY_VALUE(topic_name) AS topic_name,
  ANY_VALUE(max_d) AS as_of_date,
  SUM(IF(d > DATE_SUB(max_d, INTERVAL 7 DAY), contacts, 0)) AS contacts_last_7d,
  SUM(IF(d <= DATE_SUB(max_d, INTERVAL 7 DAY) AND d > DATE_SUB(max_d, INTERVAL 35 DAY), contacts, 0)) / 4 AS prior_weekly_avg,
  MIN(d) AS first_seen_date
FROM daily CROSS JOIN bounds
GROUP BY topic_id;

CREATE OR REPLACE TABLE `__PROJECT__.__DATASET__.data_freshness` AS
SELECT
  'Genesys interaction metrics' AS dataset,
  MAX(ingested_at) AS last_loaded_at,
  MAX(started_at) AS latest_event_at,
  COUNT(DISTINCT conversation_id) AS records,
  COUNT(*) - COUNT(DISTINCT conversation_id) AS duplicates_removed,
  COUNTIF(TIMESTAMP_DIFF(ingested_at, started_at, HOUR) > 36) AS late_arriving_records
FROM `__PROJECT__.__DATASET__.raw_interaction_metrics`
UNION ALL
SELECT
  'Conversation transcripts',
  MAX(ingested_at), MAX(started_at), COUNT(DISTINCT conversation_id),
  COUNT(*) - COUNT(DISTINCT conversation_id),
  COUNTIF(TIMESTAMP_DIFF(ingested_at, started_at, HOUR) > 36)
FROM `__PROJECT__.__DATASET__.raw_transcripts`
UNION ALL
SELECT
  'AI conversation insights',
  MAX(enriched_at), NULL, COUNT(DISTINCT conversation_id), 0, 0
FROM `__PROJECT__.__DATASET__.conversation_insights`;
