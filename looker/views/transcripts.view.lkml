view: transcripts {
  sql_table_name: `@{GCP_PROJECT}.@{DATASET}.raw_transcripts` ;;
  label: "Transcript (restricted)"

  dimension: conversation_id {
    primary_key: yes
    hidden: yes
    sql: ${TABLE}.conversation_id ;;
  }

  dimension: transcript_text {
    description: "PII-redacted transcript. Only visible to roles with the voc_can_view_transcripts attribute. Deleted after 60 days in production."
    required_access_grants: [can_view_transcripts]
    sql: ${TABLE}.transcript_text ;;
  }

  dimension: transcript_formatted {
    label: "Transcript"
    required_access_grants: [can_view_transcripts]
    sql: REPLACE(${TABLE}.transcript_text, '\n', '<br>') ;;
    html: <div style="font-size: 12px; line-height: 1.5;">{{ value }}</div> ;;
  }

  dimension: turn_count {
    type: number
    sql: ${TABLE}.turn_count ;;
  }
}
