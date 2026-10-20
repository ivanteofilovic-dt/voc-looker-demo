-- Open-ended, structured insight extraction from every transcript with Gemini.
-- Incremental + idempotent: only conversations without a stored insight are sent, so the
-- script can simply be re-run until nothing is missing (failed rows are retried).
-- Privacy rule: transcripts from the complaints queue (Reklamation) are never sent to the model.

DECLARE extraction_prompt STRING DEFAULT """
You are a Voice-of-the-Customer analyst for a Swedish telecom operator (mobile, fixed broadband, TV).
Analyse the customer service conversation transcript below. It may be in Swedish or English.
Personal data is already redacted (e.g. [CUSTOMER_NAME], [PERSONNUMMER]).

Rules:
- Do NOT use a predefined category list. Describe what the customer actually contacted us about, in specific business language.
- Write every field in English, except evidence_quote, which must be copied verbatim from the customer's own words in the original language.
- Only state what is supported by the transcript. If something is not mentioned, return an empty string, false or 0.

Fields:
- summary: 1-2 sentences describing what happened and the outcome.
- primary_issue: the main reason for contact as a short, specific label of 3-7 words, lower case (e.g. "wi-fi drops after router update", "final invoice amount unclear"). Describe the customer's problem, not the agent's action.
- secondary_issues: other distinct issues the customer raised in the same conversation, same label style. Empty array if none.
- journey_step: exactly one of: purchase, delivery & installation, onboarding & activation, usage & technical support, billing & payment, plan change & migration, termination & retention.
- product_area: exactly one of: Mobile, Fixed Broadband, TV, Other.
- hardware_model: device or router model explicitly mentioned, else empty.
- network_operator: fibre/network owner explicitly mentioned (a partner network, not a competitor the customer is leaving), else empty.
- customer_sentiment: negative, neutral or positive, as the customer feels at the end of the conversation.
- sentiment_score: from -1.0 (very negative) to 1.0 (very positive).
- trigger_event: what happened before the contact that caused it (e.g. an email, an update, an order, a failed self-service attempt), else empty.
- root_cause: the underlying cause of the problem as far as the conversation reveals it, else empty.
- resolution: what the agent or bot did or offered.
- resolved_in_contact: true if the issue was solved during this contact.
- failure_demand: true if the contact was caused by something not working as intended or by unclear communication (an avoidable contact); false for value-creating requests such as purchases or upgrades.
- self_service_attempted: true if the customer says they tried the app, website, My Pages or a bot first.
- repeat_contact_mentioned: true if the customer says they have contacted us about this before.
- churn_risk: low, medium or high.
- termination_requested: true if the customer asks to cancel or terminate a subscription.
- competitor_name: competitor operator explicitly mentioned, else empty.
- competitor_offer: the competitor's offer as described by the customer, else empty.
- competitor_price_sek: monthly price of that offer in SEK if stated, else 0.
- evidence_quote: the single customer sentence that best supports primary_issue, verbatim.
- confidence: 0.0-1.0, your confidence that primary_issue and root_cause are correct.
""";

CREATE TEMP FUNCTION clean(x STRING) AS (
  IF(LOWER(TRIM(x)) IN ('', 'none', 'null', 'n/a', 'na', 'unknown', 'not mentioned', 'not applicable'), NULL, TRIM(x))
);

CREATE TABLE IF NOT EXISTS `__PROJECT__.__DATASET__.conversation_insights` (
  conversation_id STRING NOT NULL,
  summary STRING,
  primary_issue STRING,
  secondary_issues ARRAY<STRING>,
  journey_step STRING,
  product_area STRING,
  hardware_model STRING,
  network_operator STRING,
  customer_sentiment STRING,
  sentiment_score FLOAT64,
  trigger_event STRING,
  root_cause STRING,
  resolution STRING,
  resolved_in_contact BOOL,
  failure_demand BOOL,
  self_service_attempted BOOL,
  repeat_contact_mentioned BOOL,
  churn_risk STRING,
  termination_requested BOOL,
  competitor_name STRING,
  competitor_offer STRING,
  competitor_price_sek FLOAT64,
  evidence_quote STRING,
  confidence FLOAT64,
  model_version STRING,
  prompt_version STRING,
  enriched_at TIMESTAMP
);

INSERT INTO `__PROJECT__.__DATASET__.conversation_insights`
SELECT
  conversation_id,
  summary,
  LOWER(clean(primary_issue)),
  ARRAY(SELECT LOWER(clean(s)) FROM UNNEST(secondary_issues) AS s WHERE clean(s) IS NOT NULL),
  LOWER(clean(journey_step)),
  clean(product_area),
  clean(hardware_model),
  clean(network_operator),
  LOWER(clean(customer_sentiment)),
  sentiment_score,
  clean(trigger_event),
  clean(root_cause),
  clean(resolution),
  resolved_in_contact,
  failure_demand,
  self_service_attempted,
  repeat_contact_mentioned,
  LOWER(clean(churn_risk)),
  termination_requested,
  clean(competitor_name),
  clean(competitor_offer),
  competitor_price_sek,
  clean(evidence_quote),
  confidence,
  '__GEMINI_ENDPOINT__',
  'voc-extract-v1',
  CURRENT_TIMESTAMP()
FROM AI.GENERATE_TABLE(
  MODEL `__PROJECT__.__DATASET__.gemini_model`,
  (
    SELECT
      t.conversation_id,
      CONCAT(extraction_prompt, '\n\nTRANSCRIPT:\n', t.transcript_text) AS prompt
    FROM `__PROJECT__.__DATASET__.raw_transcripts` AS t
    JOIN (
      SELECT conversation_id, ANY_VALUE(queue_name) AS queue_name
      FROM `__PROJECT__.__DATASET__.raw_interaction_metrics`
      GROUP BY conversation_id
    ) AS m USING (conversation_id)
    WHERE m.queue_name NOT IN ('B2C_Reklamation')
      AND t.conversation_id NOT IN (SELECT conversation_id FROM `__PROJECT__.__DATASET__.conversation_insights`)
  ),
  STRUCT(
    """summary STRING, primary_issue STRING, secondary_issues ARRAY<STRING>, journey_step STRING,
       product_area STRING, hardware_model STRING, network_operator STRING, customer_sentiment STRING,
       sentiment_score FLOAT64, trigger_event STRING, root_cause STRING, resolution STRING,
       resolved_in_contact BOOL, failure_demand BOOL, self_service_attempted BOOL,
       repeat_contact_mentioned BOOL, churn_risk STRING, termination_requested BOOL,
       competitor_name STRING, competitor_offer STRING, competitor_price_sek FLOAT64,
       evidence_quote STRING, confidence FLOAT64""" AS output_schema,
    0.0 AS temperature,
    2048 AS max_output_tokens
  )
)
WHERE status = '';

SELECT
  (SELECT COUNT(*) FROM `__PROJECT__.__DATASET__.conversation_insights`) AS enriched,
  (SELECT COUNT(*) FROM `__PROJECT__.__DATASET__.raw_transcripts`) AS transcripts;
