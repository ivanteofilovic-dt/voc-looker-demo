connection: "@{CONNECTION_NAME}"
label: "Voice of the Customer"

include: "/views/*.view.lkml"
include: "/dashboards/*.dashboard.lookml"

week_start_day: monday

datagroup: voc_daily_refresh {
  sql_trigger: SELECT MAX(enriched_at) FROM `@{GCP_PROJECT}.@{DATASET}.conversation_insights` ;;
  max_cache_age: "24 hours"
  description: "Cache is invalidated when the daily enrichment run finishes."
}
persist_with: voc_daily_refresh

# Transcript text and the AI transcript search are restricted to a few roles (e.g. QA, VoC analysts).
access_grant: can_view_transcripts {
  user_attribute: voc_can_view_transcripts
  allowed_values: ["yes"]
}

explore: conversation_facts {
  label: "Customer Conversations"
  description: "Every call and chat with operational KPIs (AHT, CSAT, repeat contacts, churn) and AI-extracted insights (topics, sentiment, root cause, triggers). Use topic fields to analyse multi-intent conversations."
  # Row-level security: B2B users only see B2B interactions, etc.
  access_filter: {
    field: conversation_facts.business_type
    user_attribute: voc_business_type
  }

  join: conversation_topics {
    view_label: "Topics (incl. secondary)"
    type: left_outer
    relationship: one_to_many
    sql_on: ${conversation_facts.conversation_id} = ${conversation_topics.conversation_id} ;;
  }

  join: topic_catalog {
    view_label: "Topics (incl. secondary)"
    type: left_outer
    relationship: many_to_one
    sql_on: ${conversation_topics.topic_id} = ${topic_catalog.topic_id} ;;
  }

  join: topic_recommendations {
    view_label: "Recommendations"
    type: left_outer
    relationship: many_to_one
    sql_on: ${conversation_topics.topic_id} = ${topic_recommendations.topic_id} ;;
  }

  join: transcripts {
    type: left_outer
    relationship: one_to_one
    required_access_grants: [can_view_transcripts]
    sql_on: ${conversation_facts.conversation_id} = ${transcripts.conversation_id} ;;
  }
}

explore: topic_trends {
  label: "Emerging Issues & Topic Trends"
  description: "Daily contacts per discovered topic with 7-day volumes, 4-week baseline, spike detection and trend status (New / Rising / Stable / Declining)."
  join: topic_recommendations {
    type: left_outer
    relationship: many_to_one
    sql_on: ${topic_trends.topic_id} = ${topic_recommendations.topic_id} ;;
  }
}

explore: topic_priority {
  label: "Issue Prioritisation"
  description: "Ranks topics by a transparent, adjustable score combining volume, handling cost, customer experience, repeat contacts and churn."
  join: topic_recommendations {
    type: left_outer
    relationship: one_to_one
    sql_on: ${topic_priority.topic_id} = ${topic_recommendations.topic_id} ;;
  }
}

explore: transcript_ai_search {
  label: "Ask the Transcripts (AI search)"
  description: "Ad-hoc semantic question over a sample of transcripts, evaluated by Gemini at query time with BigQuery AI.IF. Use for questions no field answers yet."
  required_access_grants: [can_view_transcripts]
  persist_for: "24 hours"
  always_filter: {
    filters: [transcript_ai_search.search_period: "30 days"]
  }
}

explore: data_freshness {
  label: "Data Freshness & Coverage"
}

explore: insight_of_the_day {
  label: "Insight of the Day"
}
