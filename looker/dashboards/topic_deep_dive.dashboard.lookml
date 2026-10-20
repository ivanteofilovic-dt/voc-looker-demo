- dashboard: topic_deep_dive
  title: "VoC – Topic Deep Dive"
  description: "Everything about one topic: trend, impact, who is affected, root causes, triggers, competitor mentions and the evidence behind it."
  layout: newspaper
  preferred_viewer: dashboards-next
  crossfilter_enabled: true

  filters:
  - name: Topic
    title: Topic
    type: field_filter
    default_value: ""
    allow_multiple_values: true
    required: false
    ui_config:
      type: tag_list
      display: popover
    model: voc
    explore: conversation_facts
    field: conversation_topics.topic_name

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

  - name: AI Confidence
    title: AI Confidence
    type: field_filter
    default_value: ""
    allow_multiple_values: true
    required: false
    ui_config:
      type: button_group
      display: inline
    model: voc
    explore: conversation_facts
    field: conversation_facts.confidence_band

  elements:

  - name: recommendation
    title: "Problem Statement & Recommended Action (AI-generated)"
    model: voc
    explore: conversation_facts
    type: looker_single_record
    fields: [conversation_topics.topic_name, topic_catalog.description, topic_recommendations.problem_statement,
             topic_recommendations.recommended_action, topic_recommendations.suggested_owner, topic_recommendations.expected_impact]
    limit: 1
    show_view_names: false
    listen:
      Topic: conversation_topics.topic_name
    row: 0
    col: 0
    width: 24
    height: 5

  - name: kpi_contacts
    title: "Contacts"
    model: voc
    explore: conversation_facts
    type: single_value
    fields: [conversation_facts.contacts]
    listen: {Topic: conversation_topics.topic_name, Date: conversation_facts.started_date, AI Confidence: conversation_facts.confidence_band}
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
    listen: {Topic: conversation_topics.topic_name, Date: conversation_facts.started_date, AI Confidence: conversation_facts.confidence_band}
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
    listen: {Topic: conversation_topics.topic_name, Date: conversation_facts.started_date, AI Confidence: conversation_facts.confidence_band}
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
    listen: {Topic: conversation_topics.topic_name, Date: conversation_facts.started_date, AI Confidence: conversation_facts.confidence_band}
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
    listen: {Topic: conversation_topics.topic_name, Date: conversation_facts.started_date, AI Confidence: conversation_facts.confidence_band}
    row: 5
    col: 16
    width: 4
    height: 3

  - name: kpi_churn
    title: "Churn Rate (30d)"
    model: voc
    explore: conversation_facts
    type: single_value
    fields: [conversation_facts.churn_rate]
    listen: {Topic: conversation_topics.topic_name, Date: conversation_facts.started_date, AI Confidence: conversation_facts.confidence_band}
    row: 5
    col: 20
    width: 4
    height: 3

  - name: daily_trend
    title: "Daily Contacts (spike days flagged in the table below)"
    model: voc
    explore: topic_trends
    type: looker_column
    fields: [topic_trends.contact_date, topic_trends.contacts]
    fill_fields: [topic_trends.contact_date]
    sorts: [topic_trends.contact_date]
    show_view_names: false
    listen:
      Topic: topic_trends.topic_name
    row: 8
    col: 0
    width: 16
    height: 6

  - name: spike_days
    title: "Spike Days"
    model: voc
    explore: topic_trends
    type: looker_grid
    fields: [topic_trends.contact_date, topic_trends.contacts, topic_trends.max_z_score]
    filters:
      topic_trends.is_spike_day: "Yes"
    sorts: [topic_trends.contact_date desc]
    limit: 20
    show_view_names: false
    listen:
      Topic: topic_trends.topic_name
    row: 8
    col: 16
    width: 8
    height: 6

  - name: by_lifetime
    title: "By Customer Lifetime"
    model: voc
    explore: conversation_facts
    type: looker_bar
    fields: [conversation_facts.tenure_band, conversation_facts.contacts]
    sorts: [conversation_facts.tenure_band]
    show_view_names: false
    listen: {Topic: conversation_topics.topic_name, Date: conversation_facts.started_date, AI Confidence: conversation_facts.confidence_band}
    row: 14
    col: 0
    width: 6
    height: 6

  - name: by_region
    title: "By Region"
    model: voc
    explore: conversation_facts
    type: looker_bar
    fields: [conversation_facts.region, conversation_facts.contacts]
    sorts: [conversation_facts.contacts desc]
    show_view_names: false
    listen: {Topic: conversation_topics.topic_name, Date: conversation_facts.started_date, AI Confidence: conversation_facts.confidence_band}
    row: 14
    col: 6
    width: 6
    height: 6

  - name: by_hardware_network
    title: "By Hardware / Network Operator"
    model: voc
    explore: conversation_facts
    type: looker_grid
    fields: [conversation_facts.hardware_model, conversation_facts.network_operator, conversation_facts.contacts, conversation_facts.repeat_contact_rate]
    sorts: [conversation_facts.contacts desc]
    limit: 10
    show_view_names: false
    listen: {Topic: conversation_topics.topic_name, Date: conversation_facts.started_date, AI Confidence: conversation_facts.confidence_band}
    row: 14
    col: 12
    width: 6
    height: 6

  - name: channel_path
    title: "Channel Switching (repeat contacts)"
    model: voc
    explore: conversation_facts
    type: looker_pie
    fields: [conversation_facts.channel_path, conversation_facts.contacts]
    filters:
      conversation_facts.is_repeat_contact: "Yes"
    sorts: [conversation_facts.contacts desc]
    show_view_names: false
    listen: {Topic: conversation_topics.topic_name, Date: conversation_facts.started_date, AI Confidence: conversation_facts.confidence_band}
    row: 14
    col: 18
    width: 6
    height: 6

  - name: root_causes
    title: "Root Causes"
    model: voc
    explore: conversation_facts
    type: looker_grid
    fields: [conversation_facts.root_cause, conversation_facts.contacts, conversation_facts.avg_aht_min, conversation_facts.repeat_contact_rate]
    filters:
      conversation_facts.root_cause: "-NULL"
    sorts: [conversation_facts.contacts desc]
    limit: 10
    show_view_names: false
    listen: {Topic: conversation_topics.topic_name, Date: conversation_facts.started_date, AI Confidence: conversation_facts.confidence_band}
    row: 20
    col: 0
    width: 12
    height: 6

  - name: competitor_mentions
    title: "Competitor Mentions"
    model: voc
    explore: conversation_facts
    type: looker_grid
    fields: [conversation_facts.competitor_name, conversation_facts.competitor_offer, conversation_facts.competitor_price_sek, conversation_facts.contacts]
    filters:
      conversation_facts.competitor_name: "-NULL"
    sorts: [conversation_facts.contacts desc]
    limit: 15
    show_view_names: false
    listen: {Topic: conversation_topics.topic_name, Date: conversation_facts.started_date, AI Confidence: conversation_facts.confidence_band}
    row: 20
    col: 12
    width: 12
    height: 6

  - name: evidence
    title: "Evidence – Customer Quotes (click a Conversation ID to open the transcript)"
    model: voc
    explore: conversation_facts
    type: looker_grid
    fields: [conversation_facts.started_date, conversation_facts.channel, conversation_facts.language, conversation_facts.evidence_quote,
             conversation_facts.summary, conversation_facts.confidence, conversation_facts.conversation_id]
    sorts: [conversation_facts.started_date desc]
    limit: 50
    show_view_names: false
    listen: {Topic: conversation_topics.topic_name, Date: conversation_facts.started_date, AI Confidence: conversation_facts.confidence_band}
    row: 26
    col: 0
    width: 24
    height: 8
