view: data_freshness {
  sql_table_name: `@{GCP_PROJECT}.@{DATASET}.data_freshness` ;;

  dimension: dataset {
    primary_key: yes
    sql: ${TABLE}.dataset ;;
  }

  dimension_group: last_loaded {
    type: time
    timeframes: [time, date]
    sql: ${TABLE}.last_loaded_at ;;
  }

  dimension_group: latest_event {
    label: "Latest Contact in Data"
    type: time
    timeframes: [time, date]
    sql: ${TABLE}.latest_event_at ;;
  }

  dimension: hours_since_load {
    type: number
    sql: TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), ${TABLE}.last_loaded_at, HOUR) ;;
  }

  dimension: freshness_status {
    sql: IF(TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), ${TABLE}.last_loaded_at, HOUR) <= 30, 'Fresh (< 24h SLA)', 'Delayed') ;;
    html: {% if value contains 'Fresh' %}<span style="color:#1e8e3e">● {{ value }}</span>{% else %}<span style="color:#d93025">● {{ value }}</span>{% endif %} ;;
  }

  measure: records {
    type: sum
    sql: ${TABLE}.records ;;
  }

  measure: duplicates_removed {
    type: sum
    sql: ${TABLE}.duplicates_removed ;;
  }

  measure: late_arriving_records {
    description: "Records that arrived more than 36h after the contact and were merged into history."
    type: sum
    sql: ${TABLE}.late_arriving_records ;;
  }
}
