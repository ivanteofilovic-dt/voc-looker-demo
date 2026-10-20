view: transcript_ai_search {
  label: "Ask the Transcripts"
  # Answers questions that no existing field covers, by letting Gemini read a deterministic sample
  # of transcripts at query time (BigQuery AI.IF). Results show sample size and an extrapolated volume.
  derived_table: {
    sql:
      WITH scope AS (
        SELECT
          t.conversation_id, t.transcript_text, f.started_at, f.channel, f.line_of_business,
          f.primary_topic, f.primary_theme, f.tenure_band, f.region, f.evidence_quote, f.summary
        FROM `@{GCP_PROJECT}.@{DATASET}.raw_transcripts` AS t
        JOIN `@{GCP_PROJECT}.@{DATASET}.conversation_facts` AS f ON f.conversation_id = t.conversation_id
        WHERE {% condition search_period %} f.started_at {% endcondition %}
          AND {% condition line_of_business_filter %} f.line_of_business {% endcondition %}
          AND f.queue_name NOT IN ('B2C_Reklamation')
          AND f.business_type IN UNNEST(ARRAY(SELECT TRIM(x) FROM UNNEST(SPLIT('{{ _user_attributes['voc_business_type'] }}', ',')) AS x))
      ),
      sample AS (
        SELECT *, COUNT(*) OVER () AS scope_size
        FROM scope
        QUALIFY ROW_NUMBER() OVER (ORDER BY FARM_FINGERPRINT(conversation_id)) <= {% parameter sample_size %}
      )
      SELECT
        s.* EXCEPT (transcript_text),
        COUNT(*) OVER () AS sample_size,
        AI.IF(
          ('Answer strictly based on this customer service transcript. Is the following statement true? Statement: ',
           {% parameter question %},
           '\nTranscript:\n', s.transcript_text),
          connection_id => '@{VERTEX_CONNECTION}'
        ) AS matches_question
      FROM sample AS s
      ;;
  }

  parameter: question {
    label: "Your question (statement to test)"
    description: "Write a yes/no statement about the conversation, e.g. 'The customer mentions they first tried to solve the issue in the app'."
    type: string
    default_value: "The customer says they first tried to solve the problem themselves in the app, website or My Pages"
  }

  parameter: sample_size {
    type: unquoted
    default_value: "300"
    allowed_value: { value: "100" }
    allowed_value: { value: "300" }
    allowed_value: { value: "1000" }
  }

  filter: search_period {
    type: date_time
  }

  filter: line_of_business_filter {
    label: "Line of Business"
    type: string
    suggest_explore: conversation_facts
    suggest_dimension: conversation_facts.line_of_business
  }

  dimension: conversation_id {
    primary_key: yes
    sql: ${TABLE}.conversation_id ;;
    link: {
      label: "Open transcript and AI insight"
      url: "/explore/voc/conversation_facts?fields=conversation_facts.conversation_id,conversation_facts.started_time,conversation_facts.summary,conversation_facts.root_cause,conversation_facts.evidence_quote,transcripts.transcript_formatted&f[conversation_facts.conversation_id]={{ value | url_encode }}"
    }
  }

  dimension_group: started {
    type: time
    timeframes: [date, week]
    sql: ${TABLE}.started_at ;;
  }

  dimension: matches_question {
    type: yesno
    sql: ${TABLE}.matches_question ;;
  }

  dimension: channel { sql: ${TABLE}.channel ;; }
  dimension: line_of_business { sql: ${TABLE}.line_of_business ;; }
  dimension: primary_topic { label: "Topic (primary)" sql: ${TABLE}.primary_topic ;; }
  dimension: primary_theme { label: "Theme (primary)" sql: ${TABLE}.primary_theme ;; }
  dimension: tenure_band { label: "Customer Lifetime" sql: ${TABLE}.tenure_band ;; }
  dimension: region { sql: ${TABLE}.region ;; }
  dimension: summary { sql: ${TABLE}.summary ;; }
  dimension: evidence_quote { sql: ${TABLE}.evidence_quote ;; }

  measure: sampled_conversations {
    type: count
  }

  measure: matching_conversations {
    type: count
    filters: [matches_question: "yes"]
    drill_fields: [conversation_id, started_date, primary_topic, summary, evidence_quote]
  }

  measure: match_rate {
    label: "Match Rate in Sample"
    type: number
    sql: ${matching_conversations} / NULLIF(${sampled_conversations}, 0) ;;
    value_format_name: percent_1
  }

  measure: estimated_total_matches {
    label: "Estimated Matches in Full Scope"
    description: "Match rate in the sample x number of conversations in scope. An estimate, not a count."
    type: number
    sql: ${match_rate} * MAX(${TABLE}.scope_size) ;;
    value_format_name: decimal_0
  }

  measure: conversations_in_scope {
    type: max
    sql: ${TABLE}.scope_size ;;
  }
}
