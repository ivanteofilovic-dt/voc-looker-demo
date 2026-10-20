view: topic_trends {
  label: "Topic Trends"
  # Built per query so that segment filters (line of business, channel) and the user's
  # business-type access also shape the baseline and spike detection.
  derived_table: {
    sql:
      WITH facts AS (
        SELECT f.conversation_id, DATE(f.started_at, 'Europe/Stockholm') AS contact_date
        FROM `@{GCP_PROJECT}.@{DATASET}.conversation_facts` AS f
        WHERE f.business_type IN UNNEST(ARRAY(SELECT TRIM(x) FROM UNNEST(SPLIT('{{ _user_attributes['voc_business_type'] }}', ',')) AS x))
          AND {% condition line_of_business_filter %} f.line_of_business {% endcondition %}
          AND {% condition channel_filter %} f.channel {% endcondition %}
      ),
      bounds AS (SELECT MIN(contact_date) AS min_d, MAX(contact_date) AS max_d FROM facts),
      days AS (SELECT d AS contact_date FROM bounds, UNNEST(GENERATE_DATE_ARRAY(min_d, max_d)) AS d),
      topics AS (SELECT topic_id, topic_name, theme FROM `@{GCP_PROJECT}.@{DATASET}.topic_catalog`),
      counts AS (
        SELECT f.contact_date, ct.topic_id, COUNT(DISTINCT f.conversation_id) AS contacts
        FROM facts AS f
        JOIN `@{GCP_PROJECT}.@{DATASET}.conversation_topics` AS ct ON ct.conversation_id = f.conversation_id
        GROUP BY 1, 2
      ),
      grid AS (
        SELECT d.contact_date, t.topic_id, t.topic_name, t.theme, IFNULL(c.contacts, 0) AS contacts
        FROM days AS d
        CROSS JOIN topics AS t
        LEFT JOIN counts AS c ON c.contact_date = d.contact_date AND c.topic_id = t.topic_id
      ),
      windowed AS (
        SELECT
          *,
          SUM(contacts) OVER (PARTITION BY topic_id ORDER BY UNIX_DATE(contact_date) RANGE BETWEEN 6 PRECEDING AND CURRENT ROW) AS contacts_7d,
          SUM(contacts) OVER (PARTITION BY topic_id ORDER BY UNIX_DATE(contact_date) RANGE BETWEEN 34 PRECEDING AND 7 PRECEDING) / 4 AS baseline_weekly_avg,
          AVG(contacts) OVER (PARTITION BY topic_id ORDER BY UNIX_DATE(contact_date) RANGE BETWEEN 28 PRECEDING AND 1 PRECEDING) AS baseline_daily_avg,
          STDDEV(contacts) OVER (PARTITION BY topic_id ORDER BY UNIX_DATE(contact_date) RANGE BETWEEN 28 PRECEDING AND 1 PRECEDING) AS baseline_daily_std
        FROM grid
      ),
      first_seen AS (
        SELECT topic_id, MIN(IF(contacts_7d >= 3, contact_date, NULL)) AS first_seen_date
        FROM windowed
        GROUP BY topic_id
      )
      SELECT
        w.*,
        fs.first_seen_date,
        SAFE_DIVIDE(w.contacts - w.baseline_daily_avg, GREATEST(IFNULL(w.baseline_daily_std, 0), 1)) AS z_score,
        SAFE_DIVIDE(w.contacts_7d, NULLIF(w.baseline_weekly_avg, 0)) AS growth_ratio,
        CASE
          WHEN w.contacts_7d < 5 THEN 'Low volume'
          WHEN fs.first_seen_date > DATE_ADD(b.min_d, INTERVAL 28 DAY)
               AND DATE_DIFF(w.contact_date, fs.first_seen_date, DAY) <= 21 THEN 'New'
          WHEN SAFE_DIVIDE(w.contacts_7d, NULLIF(w.baseline_weekly_avg, 0)) >= 1.5 THEN 'Rising'
          WHEN SAFE_DIVIDE(w.contacts_7d, NULLIF(w.baseline_weekly_avg, 0)) <= 0.67 THEN 'Declining'
          ELSE 'Stable'
        END AS trend_status,
        w.contact_date = b.max_d AS is_latest_date
      FROM windowed AS w
      JOIN first_seen AS fs ON fs.topic_id = w.topic_id
      CROSS JOIN bounds AS b
      ;;
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

  dimension: pk {
    primary_key: yes
    hidden: yes
    sql: CONCAT(${TABLE}.topic_id, '|', CAST(${TABLE}.contact_date AS STRING)) ;;
  }

  dimension_group: contact {
    label: "Contact"
    type: time
    datatype: date
    timeframes: [date, week, month]
    convert_tz: no
    sql: ${TABLE}.contact_date ;;
  }

  dimension: topic_id {
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

  dimension: is_latest_date {
    label: "Is Latest Day in Data"
    description: "Use to show the current status of every topic."
    type: yesno
    sql: ${TABLE}.is_latest_date ;;
  }

  dimension: trend_status {
    description: "New = first seen in the last 21 days; Rising = last 7 days >= 1.5x the 4-week weekly average; Declining <= 0.67x; Low volume < 5 contacts in 7 days."
    sql: ${TABLE}.trend_status ;;
    html:
      {% if value == 'New' %}<span style="background:#d93025;color:white;padding:2px 6px;border-radius:4px;">NEW</span>
      {% elsif value == 'Rising' %}<span style="background:#f29900;color:white;padding:2px 6px;border-radius:4px;">RISING</span>
      {% else %}{{ value }}{% endif %} ;;
  }

  dimension: is_emerging {
    type: yesno
    sql: ${TABLE}.trend_status IN ('New', 'Rising') ;;
  }

  dimension: is_spike_day {
    description: "Daily volume at least 3 standard deviations above the previous 28 days and at least 5 contacts."
    type: yesno
    sql: ${TABLE}.z_score >= 3 AND ${TABLE}.contacts >= 5 ;;
  }

  dimension: first_seen_date {
    type: date
    datatype: date
    convert_tz: no
    sql: ${TABLE}.first_seen_date ;;
  }

  measure: contacts {
    description: "Contacts mentioning the topic (primary or secondary reason)."
    type: sum
    sql: ${TABLE}.contacts ;;
  }

  measure: contacts_last_7_days {
    description: "Rolling 7-day contacts as of the day in the row. Use with Is Latest Day = Yes."
    type: max
    sql: ${TABLE}.contacts_7d ;;
  }

  measure: baseline_weekly_avg {
    label: "Baseline Contacts per Week"
    description: "Average weekly contacts in the 4 weeks before the current 7-day window."
    type: max
    sql: ${TABLE}.baseline_weekly_avg ;;
    value_format_name: decimal_1
  }

  measure: growth_vs_baseline {
    label: "Growth vs Baseline (x)"
    type: max
    sql: ${TABLE}.growth_ratio ;;
    value_format: "0.0\"x\""
  }

  measure: max_z_score {
    type: max
    sql: ${TABLE}.z_score ;;
    value_format_name: decimal_1
  }

  measure: spike_days {
    type: count
    filters: [is_spike_day: "yes"]
  }
}
