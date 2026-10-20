view: conversation_topics {
  sql_table_name: `@{GCP_PROJECT}.@{DATASET}.conversation_topics` ;;
  description: "Bridge table: one row per conversation and topic. A conversation can have several topics (multi-intent)."

  dimension: pk {
    primary_key: yes
    hidden: yes
    sql: CONCAT(${TABLE}.conversation_id, '|', ${TABLE}.topic_id) ;;
  }

  dimension: conversation_id {
    hidden: yes
    sql: ${TABLE}.conversation_id ;;
  }

  dimension: topic_id {
    hidden: yes
    sql: ${TABLE}.topic_id ;;
  }

  dimension: topic_name {
    label: "Topic (any mention)"
    description: "Discovered topic, counting both primary and secondary reasons in a conversation."
    sql: ${TABLE}.topic_name ;;
    link: {
      label: "Topic deep dive"
      url: "/dashboards/voc::topic_deep_dive?Topic={{ value | url_encode }}&Date=28%20days"
    }
  }

  dimension: theme {
    label: "Theme (any mention)"
    sql: ${TABLE}.theme ;;
  }

  dimension: is_primary {
    label: "Is Primary Reason"
    type: yesno
    sql: ${TABLE}.is_primary ;;
  }

  dimension: mention_type {
    sql: IF(${TABLE}.is_primary, 'Primary reason', 'Secondary reason') ;;
  }

  dimension: issue_label {
    label: "Issue Label (raw AI)"
    sql: ${TABLE}.issue_label ;;
  }

  measure: topic_mentions {
    description: "Conversation-topic pairs. Larger than Contacts when conversations have several topics."
    type: count
  }
}
