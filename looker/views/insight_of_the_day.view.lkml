view: insight_of_the_day {
  sql_table_name: `@{GCP_PROJECT}.@{DATASET}.insight_of_the_day` ;;

  dimension: topic_id {
    primary_key: yes
    hidden: yes
    sql: ${TABLE}.topic_id ;;
  }

  dimension: headline {
    sql: ${TABLE}.headline ;;
    html: <div style="font-size: 20px; font-weight: 600;">{{ value }}</div> ;;
  }

  dimension: explanation {
    sql: ${TABLE}.explanation ;;
  }

  dimension: topic_name {
    sql: ${TABLE}.topic_name ;;
    link: {
      label: "Topic deep dive"
      url: "/dashboards/voc::topic_deep_dive?Topic={{ value | url_encode }}&Date=28%20days"
    }
  }

  dimension: contacts_last_7d {
    type: number
    sql: ${TABLE}.contacts_last_7d ;;
  }

  dimension: prior_weekly_avg {
    type: number
    sql: ${TABLE}.prior_weekly_avg ;;
    value_format_name: decimal_1
  }

  dimension_group: as_of {
    type: time
    datatype: date
    timeframes: [date]
    sql: ${TABLE}.as_of_date ;;
  }
}
