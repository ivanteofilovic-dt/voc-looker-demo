- dashboard: voc_start_page
  title: "Voice of the Customer – Start Page"
  description: "High-level trends, emerging issues and prioritised problems from all customer conversations."
  layout: newspaper
  preferred_viewer: dashboards-next
  crossfilter_enabled: true
  refresh: 1 hour

  filters:
  - name: Date
    title: Date
    type: field_filter
    default_value: 28 days
    allow_multiple_values: true
    required: false
    ui_config:
      type: relative_timeframes
      display: inline
    model: voc
    explore: conversation_facts
    field: conversation_facts.started_date

  - name: Line of Business
    title: Line of Business
    type: field_filter
    default_value: ""
    allow_multiple_values: true
    required: false
    ui_config:
      type: tag_list
      display: popover
    model: voc
    explore: conversation_facts
    field: conversation_facts.line_of_business

  - name: Channel
    title: Channel
    type: field_filter
    default_value: ""
    allow_multiple_values: true
    required: false
    ui_config:
      type: button_group
      display: inline
    model: voc
    explore: conversation_facts
    field: conversation_facts.channel

  elements:

  # ------------------------------------------------------------ row 0: insight of the day + freshness
  - name: insight_of_the_day
    title: "Insight of the Day"
    model: voc
    explore: insight_of_the_day
    type: looker_single_record
    fields: [insight_of_the_day.headline, insight_of_the_day.explanation, insight_of_the_day.topic_name,
             insight_of_the_day.contacts_last_7d, insight_of_the_day.prior_weekly_avg]
    limit: 1
    show_view_names: false
    row: 0
    col: 0
    width: 16
    height: 5

  - name: data_freshness
    title: "Data Freshness"
    model: voc
    explore: data_freshness
    type: looker_grid
    fields: [data_freshness.dataset, data_freshness.last_loaded_time, data_freshness.freshness_status,
             data_freshness.records, data_freshness.late_arriving_records]
    sorts: [data_freshness.dataset]
    show_view_names: false
    show_row_numbers: false
    row: 0
    col: 16
    width: 8
    height: 5

  # ------------------------------------------------------------ row 1: KPIs
  - name: kpi_contacts
    title: "Contacts"
    model: voc
    explore: conversation_facts
    type: single_value
    fields: [conversation_facts.contacts]
    note_text: "Calls + chats in the selected period"
    listen:
      Date: conversation_facts.started_date
      Line of Business: conversation_facts.line_of_business
      Channel: conversation_facts.channel
    row: 5
    col: 0
    width: 4
    height: 3

  - name: kpi_customers
    title: "Unique Customers"
    model: voc
    explore: conversation_facts
    type: single_value
    fields: [conversation_facts.unique_customers]
    listen:
      Date: conversation_facts.started_date
      Line of Business: conversation_facts.line_of_business
      Channel: conversation_facts.channel
    row: 5
    col: 4
    width: 4
    height: 3

  - name: kpi_aht
    title: "Avg AHT (min)"
    model: voc
    explore: conversation_facts
    type: single_value
    fields: [conversation_facts.avg_aht_min]
    listen:
      Date: conversation_facts.started_date
      Line of Business: conversation_facts.line_of_business
      Channel: conversation_facts.channel
    row: 5
    col: 8
    width: 4
    height: 3

  - name: kpi_csat
    title: "Avg CSAT"
    model: voc
    explore: conversation_facts
    type: single_value
    fields: [conversation_facts.avg_csat]
    listen:
      Date: conversation_facts.started_date
      Line of Business: conversation_facts.line_of_business
      Channel: conversation_facts.channel
    row: 5
    col: 12
    width: 4
    height: 3

  - name: kpi_repeat
    title: "Repeat Contact Rate (7d)"
    model: voc
    explore: conversation_facts
    type: single_value
    fields: [conversation_facts.repeat_contact_rate]
    listen:
      Date: conversation_facts.started_date
      Line of Business: conversation_facts.line_of_business
      Channel: conversation_facts.channel
    row: 5
    col: 16
    width: 4
    height: 3

  - name: kpi_failure_demand
    title: "Failure Demand Share"
    model: voc
    explore: conversation_facts
    type: single_value
    fields: [conversation_facts.failure_demand_share]
    listen:
      Date: conversation_facts.started_date
      Line of Business: conversation_facts.line_of_business
      Channel: conversation_facts.channel
    row: 5
    col: 20
    width: 4
    height: 3

  # ------------------------------------------------------------ row 2: emerging issues + priority
  - name: emerging_issues
    title: "Emerging Issues (status as of latest day)"
    model: voc
    explore: topic_trends
    type: looker_grid
    fields: [topic_trends.topic_name, topic_trends.trend_status, topic_trends.first_seen_date,
             topic_trends.contacts_last_7_days, topic_trends.baseline_weekly_avg, topic_trends.growth_vs_baseline]
    filters:
      topic_trends.is_latest_date: "Yes"
      topic_trends.is_emerging: "Yes"
    sorts: [topic_trends.contacts_last_7_days desc]
    limit: 10
    show_view_names: false
    show_row_numbers: false
    listen:
      Line of Business: topic_trends.line_of_business_filter
      Channel: topic_trends.channel_filter
    row: 8
    col: 0
    width: 10
    height: 7

  - name: priority_ranking
    title: "Where to Focus – Prioritised Problems"
    model: voc
    explore: topic_priority
    type: looker_grid
    fields: [topic_priority.topic_name, topic_priority.priority_score, topic_priority.contacts,
             topic_priority.handling_cost_sek, topic_priority.repeat_rate, topic_priority.churn_rate,
             topic_priority.score_breakdown, topic_recommendations.suggested_owner]
    sorts: [topic_priority.priority_score desc]
    limit: 10
    show_view_names: false
    show_row_numbers: true
    listen:
      Date: topic_priority.period
      Line of Business: topic_priority.line_of_business_filter
      Channel: topic_priority.channel_filter
    row: 8
    col: 10
    width: 14
    height: 7

  # ------------------------------------------------------------ row 3: trends
  - name: weekly_trend_by_theme
    title: "Weekly Contacts by Theme"
    model: voc
    explore: conversation_facts
    type: looker_area
    fields: [conversation_facts.started_week, conversation_facts.primary_theme, conversation_facts.contacts]
    pivots: [conversation_facts.primary_theme]
    fill_fields: [conversation_facts.started_week]
    sorts: [conversation_facts.started_week]
    stacking: normal
    show_view_names: false
    listen:
      Line of Business: conversation_facts.line_of_business
      Channel: conversation_facts.channel
    row: 15
    col: 0
    width: 12
    height: 7

  - name: top_topics
    title: "Top Topics – Volume, AHT and CSAT"
    model: voc
    explore: conversation_facts
    type: looker_bar
    fields: [conversation_facts.primary_topic, conversation_facts.contacts, conversation_facts.avg_aht_min, conversation_facts.avg_csat]
    filters:
      conversation_facts.classification_status: "Classified"
    sorts: [conversation_facts.contacts desc]
    limit: 12
    show_view_names: false
    y_axes:
    - label: ""
      orientation: bottom
      series:
      - id: conversation_facts.contacts
        name: Contacts
    hidden_fields: [conversation_facts.avg_aht_min, conversation_facts.avg_csat]
    listen:
      Date: conversation_facts.started_date
      Line of Business: conversation_facts.line_of_business
      Channel: conversation_facts.channel
    row: 15
    col: 12
    width: 12
    height: 7

  # ------------------------------------------------------------ row 4: experience + journeys
  - name: sentiment_by_theme
    title: "Customer Sentiment by Theme"
    model: voc
    explore: conversation_facts
    type: looker_bar
    fields: [conversation_facts.primary_theme, conversation_facts.customer_sentiment, conversation_facts.contacts]
    pivots: [conversation_facts.customer_sentiment]
    filters:
      conversation_facts.classification_status: "Classified"
    sorts: [conversation_facts.primary_theme, conversation_facts.customer_sentiment]
    stacking: percent
    show_view_names: false
    series_colors:
      negative - conversation_facts.contacts: "#d93025"
      neutral - conversation_facts.contacts: "#9aa0a6"
      positive - conversation_facts.contacts: "#1e8e3e"
    listen:
      Date: conversation_facts.started_date
      Line of Business: conversation_facts.line_of_business
      Channel: conversation_facts.channel
    row: 22
    col: 0
    width: 12
    height: 7

  - name: triggers_before_contact
    title: "Most Common Triggers Before Contact"
    model: voc
    explore: conversation_facts
    type: looker_grid
    fields: [conversation_facts.trigger_event, conversation_facts.contacts, conversation_facts.self_service_attempt_rate,
             conversation_facts.repeat_contact_rate]
    filters:
      conversation_facts.trigger_event: "-NULL"
    sorts: [conversation_facts.contacts desc]
    limit: 10
    show_view_names: false
    listen:
      Date: conversation_facts.started_date
      Line of Business: conversation_facts.line_of_business
      Channel: conversation_facts.channel
    row: 22
    col: 12
    width: 12
    height: 7
