view: topic_priority {
  label: "Issue Prioritisation"
  # Transparent ranking: every component is a percentile rank (0-1) across topics in scope,
  # combined with user-adjustable weights. Change the weights in the filter bar and the ranking updates.
  derived_table: {
    sql:
      WITH base AS (
        SELECT ct.topic_id, ct.topic_name, ct.theme, f.conversation_id, f.customer_key, f.aht_sec,
               f.csat_score, f.sentiment_score, f.followed_by_repeat_7d, f.churned_within_30d, f.failure_demand
        FROM `@{GCP_PROJECT}.@{DATASET}.conversation_topics` AS ct
        JOIN `@{GCP_PROJECT}.@{DATASET}.conversation_facts` AS f ON f.conversation_id = ct.conversation_id
        WHERE {% condition period %} f.started_at {% endcondition %}
          AND {% condition line_of_business_filter %} f.line_of_business {% endcondition %}
          AND {% condition channel_filter %} f.channel {% endcondition %}
          AND f.business_type IN UNNEST(ARRAY(SELECT TRIM(x) FROM UNNEST(SPLIT('{{ _user_attributes['voc_business_type'] }}', ',')) AS x))
      ),
      agg AS (
        SELECT
          topic_id,
          ANY_VALUE(topic_name) AS topic_name,
          ANY_VALUE(theme) AS theme,
          COUNT(DISTINCT conversation_id) AS contacts,
          COUNT(DISTINCT customer_key) AS customers,
          SUM(aht_sec) / 60 * @{COST_PER_HANDLED_MINUTE_SEK} AS handling_cost_sek,
          AVG(aht_sec) / 60 AS avg_aht_min,
          AVG(csat_score) AS avg_csat,
          AVG(sentiment_score) AS avg_sentiment,
          AVG(IF(followed_by_repeat_7d, 1, 0)) AS repeat_rate,
          AVG(IF(churned_within_30d, 1, 0)) AS churn_rate,
          AVG(IF(failure_demand, 1, 0)) AS failure_demand_share
        FROM base
        GROUP BY topic_id
        HAVING COUNT(DISTINCT conversation_id) >= 10
      ),
      scored AS (
        SELECT
          *,
          PERCENT_RANK() OVER (ORDER BY contacts) AS volume_score,
          PERCENT_RANK() OVER (ORDER BY handling_cost_sek) AS cost_score,
          PERCENT_RANK() OVER (ORDER BY IFNULL(avg_sentiment, 0) DESC) AS experience_score,
          PERCENT_RANK() OVER (ORDER BY repeat_rate) AS repeat_score,
          PERCENT_RANK() OVER (ORDER BY churn_rate) AS churn_score
        FROM agg
      )
      SELECT
        *,
        100 * (
            {% parameter weight_volume %} * volume_score
          + {% parameter weight_cost %} * cost_score
          + {% parameter weight_experience %} * experience_score
          + {% parameter weight_repeat %} * repeat_score
          + {% parameter weight_churn %} * churn_score
        ) / NULLIF({% parameter weight_volume %} + {% parameter weight_cost %} + {% parameter weight_experience %}
                   + {% parameter weight_repeat %} + {% parameter weight_churn %}, 0) AS priority_score
      FROM scored
      ;;
  }

  filter: period {
    label: "Period"
    type: date_time
  }

  filter: line_of_business_filter {
    label: "Line of Business"
    type: string
    suggest_explore: conversation_facts
    suggest_dimension: conversation_facts.line_of_business
  }

  filter: channel_filter {
    label: "Channel"
    type: string
    suggest_explore: conversation_facts
    suggest_dimension: conversation_facts.channel
  }

  parameter: weight_volume {
    label: "Weight: Volume"
    type: number
    default_value: "0.30"
  }

  parameter: weight_cost {
    label: "Weight: Handling Cost"
    type: number
    default_value: "0.20"
  }

  parameter: weight_experience {
    label: "Weight: Customer Experience"
    type: number
    default_value: "0.20"
  }

  parameter: weight_repeat {
    label: "Weight: Repeat Contacts"
    type: number
    default_value: "0.15"
  }

  parameter: weight_churn {
    label: "Weight: Churn"
    type: number
    default_value: "0.15"
  }

  dimension: topic_id {
    primary_key: yes
    hidden: yes
    sql: ${TABLE}.topic_id ;;
  }

  dimension: topic_name {
    label: "Topic"
    sql: ${TABLE}.topic_name ;;
    link: {
      label: "Topic deep dive"
      url: "/dashboards/voc::topic_deep_dive?Topic={{ value | url_encode }}&Date=28%20days"
    }
  }

  dimension: theme {
    sql: ${TABLE}.theme ;;
  }

  dimension: priority_score_dim {
    hidden: yes
    type: number
    sql: ${TABLE}.priority_score ;;
  }

  dimension: score_breakdown {
    label: "Why this rank?"
    description: "Percentile (0-100) of each component versus the other topics in scope."
    sql: FORMAT('Volume %d | Cost %d | Experience %d | Repeat %d | Churn %d',
                CAST(ROUND(100 * ${TABLE}.volume_score) AS INT64), CAST(ROUND(100 * ${TABLE}.cost_score) AS INT64),
                CAST(ROUND(100 * ${TABLE}.experience_score) AS INT64), CAST(ROUND(100 * ${TABLE}.repeat_score) AS INT64),
                CAST(ROUND(100 * ${TABLE}.churn_score) AS INT64)) ;;
  }

  dimension: is_failure_demand {
    label: "Mostly Failure Demand"
    type: yesno
    sql: ${TABLE}.failure_demand_share >= 0.5 ;;
  }

  measure: priority_score {
    description: "0-100. Weighted average of percentile ranks for volume, handling cost, experience (sentiment), repeat contact rate and churn rate."
    type: max
    sql: ${TABLE}.priority_score ;;
    value_format_name: decimal_0
  }

  measure: contacts {
    type: sum
    sql: ${TABLE}.contacts ;;
  }

  measure: unique_customers {
    type: sum
    sql: ${TABLE}.customers ;;
  }

  measure: handling_cost_sek {
    label: "Handling Cost (SEK)"
    type: sum
    sql: ${TABLE}.handling_cost_sek ;;
    value_format: "#,##0"
  }

  measure: avg_aht_min {
    label: "Avg AHT (min)"
    type: max
    sql: ${TABLE}.avg_aht_min ;;
    value_format_name: decimal_1
  }

  measure: avg_csat {
    label: "Avg CSAT"
    type: max
    sql: ${TABLE}.avg_csat ;;
    value_format_name: decimal_2
  }

  measure: avg_sentiment {
    type: max
    sql: ${TABLE}.avg_sentiment ;;
    value_format_name: decimal_2
  }

  measure: repeat_rate {
    label: "Repeat Contact Rate (7d)"
    type: max
    sql: ${TABLE}.repeat_rate ;;
    value_format_name: percent_1
  }

  measure: churn_rate {
    label: "Churn Rate (30d)"
    type: max
    sql: ${TABLE}.churn_rate ;;
    value_format_name: percent_1
  }

  measure: failure_demand_share {
    type: max
    sql: ${TABLE}.failure_demand_share ;;
    value_format_name: percent_0
  }
}
