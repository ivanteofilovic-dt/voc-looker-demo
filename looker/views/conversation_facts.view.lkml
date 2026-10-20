view: conversation_facts {
  sql_table_name: `@{GCP_PROJECT}.@{DATASET}.conversation_facts` ;;
  label: "Conversations"

  # ---------------------------------------------------------------- identifiers

  dimension: conversation_id {
    primary_key: yes
    label: "Conversation ID"
    description: "Genesys conversation ID. Click to open the transcript (restricted roles)."
    sql: ${TABLE}.conversation_id ;;
    link: {
      label: "Open transcript and AI insight"
      url: "/explore/voc/conversation_facts?fields=conversation_facts.conversation_id,conversation_facts.started_time,conversation_facts.summary,conversation_facts.root_cause,conversation_facts.evidence_quote,conversation_facts.confidence,transcripts.transcript_formatted&f[conversation_facts.conversation_id]={{ value | url_encode }}&vis_config=%7B%22type%22%3A%22looker_single_record%22%7D"
    }
  }

  dimension: customer_key {
    hidden: yes
    description: "Pseudonymised customer key. Used for unique-customer counts and journey stitching; never shown to users."
    sql: ${TABLE}.customer_key ;;
  }

  # ---------------------------------------------------------------- time

  dimension_group: started {
    label: "Contact"
    type: time
    timeframes: [raw, time, hour_of_day, date, day_of_week, week, month, quarter]
    sql: ${TABLE}.started_at ;;
  }

  # ---------------------------------------------------------------- operational context (Genesys)

  dimension: channel {
    group_label: "Contact context"
    description: "voice or chat."
    sql: ${TABLE}.channel ;;
  }

  dimension: contact_type {
    group_label: "Contact context"
    description: "inbound, callback or chat."
    sql: ${TABLE}.contact_type ;;
  }

  dimension: queue_name {
    group_label: "Contact context"
    sql: ${TABLE}.queue_name ;;
  }

  dimension: business_type {
    group_label: "Customer"
    description: "B2C or B2B (from the Genesys queue grouping)."
    sql: ${TABLE}.business_type ;;
  }

  dimension: line_of_business {
    group_label: "Customer"
    label: "Line of Business (value chain)"
    description: "Mobile, Fixed Broadband or TV – used for value-chain / P&L views."
    sql: ${TABLE}.line_of_business ;;
  }

  dimension: region {
    group_label: "Customer"
    sql: ${TABLE}.region ;;
  }

  dimension: tenure_months {
    group_label: "Customer"
    type: number
    sql: ${TABLE}.tenure_months ;;
  }

  dimension: tenure_band {
    group_label: "Customer"
    label: "Customer Lifetime"
    description: "Relationship length at time of contact: 0-90 days, 3-12 months, 1-2 years, 2-5 years, 5-10 years, 10+ years."
    sql: ${TABLE}.tenure_band ;;
    order_by_field: tenure_band_sort
  }

  dimension: tenure_band_sort {
    hidden: yes
    type: number
    sql: ${TABLE}.tenure_band_sort ;;
  }

  dimension: language {
    group_label: "Contact context"
    sql: ${TABLE}.language ;;
  }

  dimension: handled_by {
    group_label: "Contact context"
    description: "agent or virtual_agent (voicebot)."
    sql: ${TABLE}.handled_by ;;
  }

  dimension: voicebot_attempted {
    group_label: "Contact context"
    type: yesno
    sql: ${TABLE}.voicebot_attempted ;;
  }

  dimension: transferred {
    group_label: "Contact context"
    type: yesno
    sql: ${TABLE}.transferred ;;
  }

  dimension: aht_sec {
    group_label: "Handling time (sec)"
    label: "AHT (sec)"
    type: number
    sql: ${TABLE}.aht_sec ;;
  }

  dimension: aht_min {
    group_label: "Handling time (sec)"
    label: "AHT (min)"
    type: number
    sql: ${TABLE}.aht_sec / 60.0 ;;
    value_format_name: decimal_1
  }

  dimension: talk_sec {
    group_label: "Handling time (sec)"
    type: number
    sql: ${TABLE}.talk_sec ;;
  }

  dimension: hold_sec {
    group_label: "Handling time (sec)"
    type: number
    sql: ${TABLE}.hold_sec ;;
  }

  dimension: mute_sec {
    group_label: "Handling time (sec)"
    type: number
    sql: ${TABLE}.mute_sec ;;
  }

  dimension: acw_sec {
    group_label: "Handling time (sec)"
    label: "After-call Work (sec)"
    type: number
    sql: ${TABLE}.acw_sec ;;
  }

  dimension: asa_sec {
    group_label: "Handling time (sec)"
    label: "Speed of Answer (sec)"
    type: number
    sql: ${TABLE}.asa_sec ;;
  }

  dimension: csat_score {
    group_label: "Outcomes"
    label: "CSAT Score"
    description: "Post-contact survey score 1-5 (survey metadata, not inferred sentiment). Empty when the customer did not answer."
    type: number
    sql: ${TABLE}.csat_score ;;
  }

  dimension: churned_within_30d {
    group_label: "Outcomes"
    label: "Churned within 30 Days"
    description: "Customer terminated within 30 days after this contact. Correlation, not causation."
    type: yesno
    sql: ${TABLE}.churned_within_30d ;;
  }

  # ---------------------------------------------------------------- journey stitching

  dimension: is_repeat_contact {
    group_label: "Journey"
    description: "Same customer had another contact (any channel, any reason) in the 7 days before this one."
    type: yesno
    sql: ${TABLE}.is_repeat_contact ;;
  }

  dimension: followed_by_repeat_7d {
    group_label: "Journey"
    label: "Followed by Repeat Contact (7d)"
    description: "Same customer contacted us again within 7 days after this contact (inverse of first-contact resolution)."
    type: yesno
    sql: ${TABLE}.followed_by_repeat_7d ;;
  }

  dimension: followed_by_same_topic_repeat_7d {
    group_label: "Journey"
    label: "Followed by Same-topic Repeat (7d)"
    type: yesno
    sql: ${TABLE}.followed_by_same_topic_repeat_7d ;;
  }

  dimension: previous_contact_channel {
    group_label: "Journey"
    description: "Channel of the customer's previous contact (for channel-switching analysis, e.g. chat -> voice)."
    sql: ${TABLE}.previous_contact_channel ;;
  }

  dimension: channel_path {
    group_label: "Journey"
    description: "Previous channel -> this channel, for repeat contacts only."
    sql: IF(${TABLE}.is_repeat_contact, CONCAT(${TABLE}.previous_contact_channel, ' -> ', ${TABLE}.channel), NULL) ;;
  }

  dimension: customer_contact_seq {
    group_label: "Journey"
    label: "Customer Contact Number"
    type: number
    sql: ${TABLE}.customer_contact_seq ;;
  }

  # ---------------------------------------------------------------- AI insight (Gemini)

  dimension: classification_status {
    group_label: "AI insight"
    description: "Classified, No transcript captured, Excluded (privacy rule) or Pending enrichment – shows coverage instead of silently dropping contacts."
    sql: ${TABLE}.classification_status ;;
  }

  dimension: primary_topic {
    group_label: "AI insight"
    label: "Topic (primary)"
    description: "Main contact reason, discovered from transcripts by clustering AI-extracted issue labels (not a predefined list)."
    sql: COALESCE(${TABLE}.primary_topic, CONCAT('(', ${TABLE}.classification_status, ')')) ;;
    link: {
      label: "Topic deep dive"
      url: "/dashboards/voc::topic_deep_dive?Topic={{ value | url_encode }}&Date=28%20days"
    }
  }

  dimension: primary_topic_id {
    hidden: yes
    sql: ${TABLE}.primary_topic_id ;;
  }

  dimension: primary_theme {
    group_label: "AI insight"
    label: "Theme (primary)"
    description: "Level-1 grouping of topics, e.g. Billing & pricing."
    sql: COALESCE(${TABLE}.primary_theme, '(not classified)') ;;
  }

  dimension: topic_count {
    group_label: "AI insight"
    label: "Number of Topics in Conversation"
    type: number
    sql: ${TABLE}.topic_count ;;
  }

  dimension: is_multi_intent {
    group_label: "AI insight"
    type: yesno
    sql: ${TABLE}.topic_count > 1 ;;
  }

  dimension: primary_issue {
    group_label: "AI insight"
    label: "Issue Label (raw AI)"
    description: "Free-text issue label Gemini extracted before clustering."
    sql: ${TABLE}.primary_issue ;;
  }

  dimension: secondary_issues {
    group_label: "AI insight"
    sql: ${TABLE}.secondary_issues ;;
  }

  dimension: summary {
    group_label: "AI insight"
    sql: ${TABLE}.summary ;;
  }

  dimension: journey_step {
    group_label: "AI insight"
    description: "purchase, delivery & installation, onboarding & activation, usage & technical support, billing & payment, plan change & migration, termination & retention."
    sql: ${TABLE}.journey_step ;;
  }

  dimension: product_area {
    group_label: "AI insight"
    description: "Product the customer talked about (may differ from the queue's line of business)."
    sql: ${TABLE}.product_area ;;
  }

  dimension: hardware_model {
    group_label: "AI insight"
    description: "Device/router model mentioned in the conversation. Empty when not mentioned (see coverage)."
    sql: COALESCE(${TABLE}.hardware_model, '(not mentioned)') ;;
  }

  dimension: network_operator {
    group_label: "AI insight"
    label: "Network Operator (fibre owner)"
    sql: COALESCE(${TABLE}.network_operator, '(not mentioned)') ;;
  }

  dimension: customer_sentiment {
    group_label: "AI insight"
    description: "negative / neutral / positive at the end of the conversation (AI-inferred, not CSAT)."
    sql: ${TABLE}.customer_sentiment ;;
  }

  dimension: sentiment_score {
    group_label: "AI insight"
    type: number
    sql: ${TABLE}.sentiment_score ;;
    value_format_name: decimal_2
  }

  dimension: trigger_event {
    group_label: "AI insight"
    label: "Trigger before Contact"
    description: "What happened before the contact, as told in the conversation (email, update, order, failed self-service...)."
    sql: ${TABLE}.trigger_event ;;
  }

  dimension: root_cause {
    group_label: "AI insight"
    sql: ${TABLE}.root_cause ;;
  }

  dimension: resolution {
    group_label: "AI insight"
    sql: ${TABLE}.resolution ;;
  }

  dimension: resolved_in_contact {
    group_label: "AI insight"
    type: yesno
    sql: ${TABLE}.resolved_in_contact ;;
  }

  dimension: failure_demand {
    group_label: "AI insight"
    description: "Yes = avoidable contact caused by something not working or unclear communication. No = value demand (e.g. upgrades)."
    type: yesno
    sql: ${TABLE}.failure_demand ;;
  }

  dimension: demand_type {
    group_label: "AI insight"
    sql: CASE WHEN ${TABLE}.failure_demand THEN 'Failure demand' WHEN ${TABLE}.failure_demand = FALSE THEN 'Value demand' END ;;
  }

  dimension: self_service_attempted {
    group_label: "AI insight"
    description: "Customer says they tried the app, web, My Pages or the bot first."
    type: yesno
    sql: ${TABLE}.self_service_attempted ;;
  }

  dimension: churn_risk {
    group_label: "AI insight"
    sql: ${TABLE}.churn_risk ;;
  }

  dimension: termination_requested {
    group_label: "AI insight"
    type: yesno
    sql: ${TABLE}.termination_requested ;;
  }

  dimension: competitor_name {
    group_label: "Competitor mentions"
    sql: ${TABLE}.competitor_name ;;
  }

  dimension: competitor_offer {
    group_label: "Competitor mentions"
    sql: ${TABLE}.competitor_offer ;;
  }

  dimension: competitor_price_sek {
    group_label: "Competitor mentions"
    label: "Competitor Price (SEK/month)"
    type: number
    sql: ${TABLE}.competitor_price_sek ;;
  }

  dimension: evidence_quote {
    group_label: "AI insight"
    description: "Verbatim customer sentence supporting the topic (PII-redacted)."
    sql: ${TABLE}.evidence_quote ;;
  }

  dimension: confidence {
    group_label: "AI insight"
    description: "Model confidence 0-1 in topic and root cause. Filter out Low for deep dives."
    type: number
    sql: ${TABLE}.confidence ;;
    value_format_name: decimal_2
  }

  dimension: confidence_band {
    group_label: "AI insight"
    sql: CASE WHEN ${TABLE}.confidence >= 0.8 THEN 'High' WHEN ${TABLE}.confidence >= 0.6 THEN 'Medium' WHEN ${TABLE}.confidence IS NOT NULL THEN 'Low' END ;;
  }

  dimension: model_version {
    group_label: "AI insight"
    sql: ${TABLE}.model_version ;;
  }

  # ================================================================ measures

  measure: contacts {
    label: "Contacts"
    description: "Number of interactions (calls + chats). One customer can have several contacts."
    type: count
    drill_fields: [conversation_drill*]
  }

  measure: unique_customers {
    label: "Unique Customers"
    description: "Distinct (pseudonymised) customers affected."
    type: count_distinct
    sql: ${customer_key} ;;
    drill_fields: [conversation_drill*]
  }

  measure: contacts_per_customer {
    type: number
    sql: ${contacts} / NULLIF(${unique_customers}, 0) ;;
    value_format_name: decimal_2
  }

  measure: share_of_contacts {
    label: "Share of Contacts"
    description: "Share of all contacts in the current result."
    type: percent_of_total
    sql: ${contacts} ;;
  }

  measure: avg_aht_min {
    label: "Avg AHT (min)"
    description: "Average handling time = talk + hold + after-call work, from Genesys (not calculated from recordings)."
    type: average
    sql: ${TABLE}.aht_sec / 60.0 ;;
    value_format_name: decimal_1
    drill_fields: [conversation_drill*]
  }

  measure: avg_asa_sec {
    label: "Avg Speed of Answer (sec)"
    type: average
    sql: ${TABLE}.asa_sec ;;
    value_format_name: decimal_0
  }

  measure: avg_mute_sec {
    label: "Avg Mute Time (sec)"
    type: average
    sql: ${TABLE}.mute_sec ;;
    value_format_name: decimal_0
  }

  measure: total_handled_hours {
    type: sum
    sql: ${TABLE}.aht_sec / 3600.0 ;;
    value_format_name: decimal_0
  }

  measure: handling_cost_sek {
    label: "Handling Cost (SEK)"
    description: "Cost proxy = handled minutes x @{COST_PER_HANDLED_MINUTE_SEK} SEK per minute."
    type: sum
    sql: ${TABLE}.aht_sec / 60.0 * @{COST_PER_HANDLED_MINUTE_SEK} ;;
    value_format: "#,##0"
  }

  measure: csat_responses {
    group_label: "CSAT"
    type: count
    filters: [csat_score: "NOT NULL"]
  }

  measure: avg_csat {
    group_label: "CSAT"
    label: "Avg CSAT (1-5)"
    description: "Average post-contact survey score. Check CSAT Responses for sample size."
    type: average
    sql: ${TABLE}.csat_score ;;
    value_format_name: decimal_2
  }

  measure: satisfied_responses {
    group_label: "CSAT"
    hidden: yes
    type: count
    filters: [csat_score: ">=4"]
  }

  measure: csat_satisfied_rate {
    group_label: "CSAT"
    label: "CSAT % Satisfied (4-5)"
    type: number
    sql: ${satisfied_responses} / NULLIF(${csat_responses}, 0) ;;
    value_format_name: percent_1
  }

  measure: repeat_contacts {
    group_label: "Repeat contacts"
    label: "Contacts Followed by Repeat (7d)"
    type: count
    filters: [followed_by_repeat_7d: "yes"]
    drill_fields: [conversation_drill*]
  }

  measure: repeat_contact_rate {
    group_label: "Repeat contacts"
    label: "Repeat Contact Rate (7d)"
    description: "Share of contacts where the same customer came back within 7 days (any channel)."
    type: number
    sql: ${repeat_contacts} / NULLIF(${contacts}, 0) ;;
    value_format_name: percent_1
  }

  measure: fcr_rate {
    group_label: "Repeat contacts"
    label: "First Contact Resolution (proxy)"
    description: "1 - repeat contact rate (7 days)."
    type: number
    sql: 1 - ${repeat_contact_rate} ;;
    value_format_name: percent_1
  }

  measure: churned_customers {
    group_label: "Churn"
    type: count_distinct
    sql: ${customer_key} ;;
    filters: [churned_within_30d: "yes"]
  }

  measure: churn_rate {
    group_label: "Churn"
    label: "Churn Rate (30d after contact)"
    description: "Share of unique customers who terminated within 30 days after a contact. Not attributed to a single interaction."
    type: number
    sql: ${churned_customers} / NULLIF(${unique_customers}, 0) ;;
    value_format_name: percent_1
  }

  measure: transfer_rate {
    type: number
    sql: ${transferred_contacts} / NULLIF(${contacts}, 0) ;;
    value_format_name: percent_1
  }

  measure: transferred_contacts {
    hidden: yes
    type: count
    filters: [transferred: "yes"]
  }

  measure: failure_demand_contacts {
    group_label: "Demand"
    type: count
    filters: [failure_demand: "yes"]
    drill_fields: [conversation_drill*]
  }

  measure: failure_demand_share {
    group_label: "Demand"
    label: "Failure Demand Share"
    type: number
    sql: ${failure_demand_contacts} / NULLIF(${contacts}, 0) ;;
    value_format_name: percent_1
  }

  measure: self_service_attempt_rate {
    group_label: "Demand"
    label: "Tried Self-service First (%)"
    type: number
    sql: ${self_service_contacts} / NULLIF(${contacts}, 0) ;;
    value_format_name: percent_1
  }

  measure: self_service_contacts {
    hidden: yes
    type: count
    filters: [self_service_attempted: "yes"]
  }

  measure: avg_sentiment {
    group_label: "Sentiment"
    type: average
    sql: ${TABLE}.sentiment_score ;;
    value_format_name: decimal_2
  }

  measure: negative_contacts {
    group_label: "Sentiment"
    hidden: yes
    type: count
    filters: [customer_sentiment: "negative"]
  }

  measure: negative_sentiment_share {
    group_label: "Sentiment"
    label: "Negative Sentiment Share"
    type: number
    sql: ${negative_contacts} / NULLIF(${contacts}, 0) ;;
    value_format_name: percent_1
  }

  measure: competitor_mentions {
    group_label: "Demand"
    type: count
    filters: [competitor_name: "-NULL"]
    drill_fields: [started_date, competitor_name, competitor_offer, competitor_price_sek, primary_topic, evidence_quote, conversation_id]
  }

  measure: transcript_coverage {
    group_label: "Data quality"
    label: "Transcript Coverage (%)"
    description: "Share of contacts with a captured transcript. Changes in coverage can look like changes in demand."
    type: number
    sql: ${with_transcript} / NULLIF(${contacts}, 0) ;;
    value_format_name: percent_1
  }

  measure: with_transcript {
    group_label: "Data quality"
    hidden: yes
    type: count
    filters: [classification_status: "-No transcript captured"]
  }

  measure: avg_confidence {
    group_label: "Data quality"
    label: "Avg AI Confidence"
    type: average
    sql: ${TABLE}.confidence ;;
    value_format_name: decimal_2
  }

  measure: contacts_last_7_days {
    group_label: "Period comparison"
    type: count
    filters: [started_date: "7 days"]
  }

  measure: contacts_previous_7_days {
    group_label: "Period comparison"
    type: count
    filters: [started_date: "14 days ago for 7 days"]
  }

  measure: contacts_change_vs_previous_week {
    group_label: "Period comparison"
    label: "Contacts Change vs Previous 7 Days"
    type: number
    sql: ${contacts_last_7_days} / NULLIF(${contacts_previous_7_days}, 0) - 1 ;;
    value_format_name: percent_0
  }

  set: conversation_drill {
    fields: [conversation_id, started_time, channel, line_of_business, primary_topic, customer_sentiment, aht_min, csat_score, summary, evidence_quote, confidence]
  }
}
