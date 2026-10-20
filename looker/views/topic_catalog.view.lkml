view: topic_catalog {
  sql_table_name: `@{GCP_PROJECT}.@{DATASET}.topic_catalog` ;;
  label: "Topic Catalog"

  dimension: topic_id {
    primary_key: yes
    sql: ${TABLE}.topic_id ;;
  }

  dimension: description {
    label: "Topic Description"
    sql: ${TABLE}.description ;;
  }

  dimension: taxonomy_version {
    description: "Version of the discovered taxonomy (changes are logged in taxonomy_change_log)."
    sql: ${TABLE}.taxonomy_version ;;
  }

  dimension_group: created {
    label: "Topic Created"
    type: time
    timeframes: [date, week]
    sql: ${TABLE}.created_at ;;
  }
}
