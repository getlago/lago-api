# frozen_string_literal: true

require "rails_helper"

require_relative "shared_examples/an_event_store"

RSpec.describe Events::Stores::ClickhouseStore, clickhouse: {clean_before: true} do
  def create_event(timestamp:, value:, properties: {}, transaction_id: SecureRandom.uuid, code: billable_metric.code, charge_filter: nil, enriched_at: nil, event_charge: nil, created_at: nil)
    attributes = {
      transaction_id: transaction_id,
      organization_id: organization.id,
      code:,
      timestamp: timestamp,
      properties: properties.merge(billable_metric.field_name => value).compact,
      value: value,
      decimal_value: value&.to_i&.to_d,
      precise_total_amount_cents: value,
      enriched_at: created_at || enriched_at || Time.current
    }

    if organization.product_events_pipeline?
      Clickhouse::ProductEventsEnriched.create!(**attributes, external_contract_id: subscription.external_id)
    else
      Clickhouse::EventsEnriched.create!(**attributes, external_subscription_id: subscription.external_id)
    end
  end

  # One insert for many events, so a large total is built without one request per event.
  def insert_events(count, timestamp:, value:, properties: {})
    rows = Array.new(count) do
      {
        transaction_id: SecureRandom.uuid,
        organization_id: organization.id,
        external_subscription_id: subscription.external_id,
        code: billable_metric.code,
        timestamp:,
        properties: properties.merge(billable_metric.field_name => value.to_s),
        value: value.to_s,
        decimal_value: value.to_d,
        precise_total_amount_cents: value.to_d,
        enriched_at: Time.current
      }
    end

    Clickhouse::EventsEnriched.insert_all(rows) # rubocop:disable Rails/SkipsModelValidations
  end

  def format_timestamp(timestamp, precision: 3)
    Time.zone.parse(timestamp).strftime("%Y-%m-%d %H:%M:%S.%#{precision}L")
  end

  it_behaves_like "an event store"

  context "with an organization on the product events pipeline" do
    it_behaves_like "an event store", product_events: true
  end

  describe "events table" do
    subject(:event_store) do
      described_class.new(
        code: billable_metric.code,
        billing_context:,
        boundaries: {from_datetime: started_at, to_datetime: started_at.end_of_month, charges_duration: 31},
        filters: {}
      )
    end

    let(:organization) { create(:organization, feature_flags: ["product_catalog"]) }
    let(:billable_metric) { create(:sum_billable_metric, organization:, field_name: "value") }
    let(:customer) { create(:customer, organization:) }
    let(:started_at) { Time.zone.parse("2026-10-01") }
    let(:contract) { create(:contract, customer:, started_at:) }
    let(:billing_context) { Billing::Context.from(contract:) }

    let(:product_event) do
      create(
        :clickhouse_product_events_enriched,
        organization:,
        external_contract_id: contract.external_id,
        code: billable_metric.code,
        timestamp: started_at + 1.day,
        properties: {"value" => "3"},
        value: "3",
        decimal_value: 3
      )
    end

    let(:subscription_event) do
      Clickhouse::EventsEnriched.create!(
        transaction_id: SecureRandom.uuid,
        organization_id: organization.id,
        external_subscription_id: contract.external_id,
        code: billable_metric.code,
        timestamp: started_at + 2.days,
        properties: {"value" => "5"},
        value: "5",
        decimal_value: 5,
        enriched_at: Time.current
      )
    end

    before do
      product_event
      subscription_event
    end

    context "with an organization on the product events pipeline" do
      before { ENV["LAGO_KAFKA_PRODUCT_RAW_EVENTS_TOPIC"] = "product_events_raw" }
      after { ENV["LAGO_KAFKA_PRODUCT_RAW_EVENTS_TOPIC"] = nil }

      it "reads the contract's events from the product events table" do
        expect(event_store.count).to eq(Events::Stores::BaseStore::AggregationResult.new(value: 1, events_count: 1))
        expect(event_store.sum(with_count: false).value).to eq(3)
        expect(event_store.events.map(&:transaction_id)).to eq([product_event.transaction_id])
      end

      it "returns the property combinations of the product events" do
        combinations = event_store.distinct_codes_and_property_combinations(codes: [billable_metric.code], filter_keys: ["value"])

        expect(combinations.map { it.first(2) }).to eq([[billable_metric.code, {"value" => "3"}]])
      end
    end

    context "without the product events topic" do
      it "reads the events_enriched table" do
        expect(event_store.count).to eq(Events::Stores::BaseStore::AggregationResult.new(value: 1, events_count: 1))
        expect(event_store.sum(with_count: false).value).to eq(5)
      end
    end
  end

  # Regression test for https://github.com/getlago/lago-api/pull/5359
  #
  # Two rows share the same (transaction_id, timestamp) but carry different
  # filterable properties. Deduplication must resolve to a single row (the
  # latest enrichment) FIRST — otherwise the same logical event could be
  # counted in multiple filter/group buckets (once per property value it ever
  # had).
  describe "filters applied after deduplication" do
    subject(:event_store) do
      described_class.new(
        code: billable_metric.code,
        billing_context: Billing::Context.from(subscription:),
        boundaries:,
        filters: {
          grouped_by: nil,
          grouped_by_values: nil,
          matching_filters: matching_filters,
          ignored_filters: [],
          charge_id: charge.id,
          charge_filter: nil
        }
      )
    end

    let(:billable_metric) { create(:sum_billable_metric, field_name: "value", code: "bm:code") }
    let(:organization) { billable_metric.organization }
    let(:charge) { create(:standard_charge, organization:, billable_metric:) }
    let(:customer) { create(:customer, organization:) }
    let(:subscription) { create(:subscription, customer:, started_at: DateTime.parse("2023-03-15")) }
    let(:subscription_started_at) { subscription.started_at.beginning_of_day }
    let(:boundaries) do
      {
        from_datetime: subscription_started_at,
        to_datetime: subscription.started_at.end_of_month.end_of_day,
        charges_duration: 31
      }
    end

    let(:transaction_id) { SecureRandom.uuid }
    let(:timestamp) { subscription_started_at + 1.day }

    before do
      Clickhouse::EventsEnriched.create!(
        transaction_id:,
        organization_id: organization.id,
        external_subscription_id: subscription.external_id,
        code: billable_metric.code,
        timestamp:,
        properties: {"value" => 1, "region" => "europe"},
        value: 1,
        decimal_value: 1.to_d,
        precise_total_amount_cents: 1,
        enriched_at: 1.minute.ago
      )

      Clickhouse::EventsEnriched.create!(
        transaction_id:,
        organization_id: organization.id,
        external_subscription_id: subscription.external_id,
        code: billable_metric.code,
        timestamp:,
        properties: {"value" => 1, "region" => "asia"},
        value: 1,
        decimal_value: 1.to_d,
        precise_total_amount_cents: 1,
        enriched_at: Time.current
      )
    end

    context "when the filter matches only the earlier (superseded) property value" do
      let(:matching_filters) { {"region" => ["europe"]} }

      it "does not count the event (latest enrichment is asia, filter excludes it)" do
        expect(event_store.count).to eq(Events::Stores::BaseStore::AggregationResult.new(value: 0, events_count: 0))
      end
    end

    context "when the filter matches only the latest property value" do
      let(:matching_filters) { {"region" => ["asia"]} }

      it "counts the deduplicated event exactly once" do
        expect(event_store.count).to eq(Events::Stores::BaseStore::AggregationResult.new(value: 1, events_count: 1))
      end
    end
  end

  describe "a late event read from a snapshot delta" do
    subject(:result) { event_store.recurring_sum(watermark: Time.current + 1.hour, period:) }

    let(:event_store) do
      described_class.new(code: billable_metric.code, billing_context: Billing::Context.from(subscription:), boundaries:, filters: {})
    end
    let(:billable_metric) { create(:sum_billable_metric, field_name: "value", recurring: true) }
    let(:organization) { billable_metric.organization }
    let(:customer) { create(:customer, organization:) }
    let(:subscription) { create(:subscription, customer:, started_at: DateTime.parse("2023-03-15")) }
    let(:boundaries) do
      {from_datetime: subscription.started_at.beginning_of_day, to_datetime: subscription.started_at.end_of_month.end_of_day, charges_duration: 31}
    end
    let(:period) do
      RecurringAggregationSnapshots::FetchService::Period.new(to_datetime: subscription.started_at + 3.days, watermark: Time.current - 1.hour)
    end
    let(:transaction_id) { SecureRandom.uuid }

    def create_copy(value:, enriched_at:)
      Clickhouse::EventsEnriched.create!(
        transaction_id:,
        organization_id: organization.id,
        external_subscription_id: subscription.external_id,
        code: billable_metric.code,
        timestamp: subscription.started_at + 1.day,
        properties: {"value" => value},
        value:,
        decimal_value: value.to_d,
        precise_total_amount_cents: value,
        enriched_at:
      )
    end

    before do
      event_store.aggregation_property = "value"
      event_store.numeric_property = true
      event_store.use_from_boundary = false
    end

    def executed_sql
      queries = []
      callback = ->(*, payload) { queries << payload[:sql] }
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { result }
      queries.join("\n")
    end

    it "turns the exact mode off for the late events" do
      expect(executed_sql).to include("enriched_at > ").and include("SETTINGS use_skip_indexes_if_final_exact_mode = 0")
    end

    context "when the inexact mode is disabled" do
      before { stub_const("ENV", ENV.to_h.merge("LAGO_DISABLE_CLICKHOUSE_INEXACT_FINAL" => "true")) }

      it "keeps the exact mode" do
        expect(executed_sql).to include("enriched_at > ")
        expect(executed_sql).not_to include("use_skip_indexes_if_final_exact_mode")
      end
    end

    context "when the event is re-sent after the watermark" do
      before do
        create_copy(value: 10, enriched_at: Time.current - 30.minutes)
        create_copy(value: 15, enriched_at: Time.current - 10.minutes)
      end

      it "counts the latest copy once" do
        expect(result).to have_attributes(value: 15, events_count: 1)
      end
    end

    context "when the event was read by the snapshot and re-sent after the watermark" do
      before do
        create_copy(value: 10, enriched_at: Time.current - 2.hours)
        create_copy(value: 15, enriched_at: Time.current - 10.minutes)
      end

      it "counts the latest copy once" do
        expect(result).to have_attributes(value: 15, events_count: 1)
      end
    end
  end

  describe "#resent_after_watermark?" do
    subject(:resent) { event_store.resent_after_watermark?(period) }

    let(:event_store) do
      described_class.new(code: billable_metric.code, billing_context: Billing::Context.from(subscription:), boundaries:, filters:)
    end
    let(:filters) { {} }
    let(:billable_metric) { create(:sum_billable_metric, field_name: "value", recurring: true) }
    let(:organization) { billable_metric.organization }
    let(:customer) { create(:customer, organization:) }
    let(:subscription) { create(:subscription, customer:, started_at: DateTime.parse("2023-03-15")) }
    let(:boundaries) do
      {from_datetime: subscription.started_at.beginning_of_day, to_datetime: subscription.started_at.end_of_month.end_of_day, charges_duration: 31}
    end
    let(:period) do
      RecurringAggregationSnapshots::FetchService::Period.new(to_datetime: subscription.started_at + 3.days, watermark: (Time.current - 1.hour).floor(3))
    end
    let(:transaction_id) { SecureRandom.uuid }
    let(:timestamp) { subscription.started_at + 1.day }

    # events_raw keeps each insert, while FINAL reads the latest one from events_enriched
    def ingest(ingested_at:, region: "eu", enriched_at: ingested_at)
      Clickhouse::EventsRaw.create!(
        organization_id: organization.id,
        external_customer_id: customer.external_id,
        external_subscription_id: subscription.external_id,
        transaction_id:,
        timestamp:,
        code: billable_metric.code,
        properties: {"value" => "1", "region" => region},
        ingested_at:
      )
      Clickhouse::EventsEnriched.create!(
        transaction_id:,
        organization_id: organization.id,
        external_subscription_id: subscription.external_id,
        code: billable_metric.code,
        timestamp:,
        properties: {"value" => "1", "region" => region},
        value: "1",
        decimal_value: 1,
        enriched_at:
      )
    end

    before do
      event_store.aggregation_property = "value"
      event_store.numeric_property = true
      event_store.use_from_boundary = false
    end

    it { is_expected.to be(false) }

    it "parses the watermark before comparing it to ingested_at, which can be a DateTime without milliseconds" do
      expect(event_store.resent_after_watermark_sql(period)).to include("ingested_at <= toDateTime64('")
    end

    context "with an event ingested by the watermark and re-sent after it" do
      before do
        ingest(ingested_at: period.watermark)
        ingest(ingested_at: period.watermark + 10.minutes)
      end

      it { is_expected.to be(true) }

      context "when the filters leave both copies out" do
        let(:filters) { {matching_filters: {"region" => ["us"]}} }

        it { is_expected.to be(true) }
      end

      context "when the event is dated after the period" do
        let(:timestamp) { period.to_datetime + 1.second }

        it { is_expected.to be(false) }
      end
    end

    context "with an event re-sent after the watermark out of the filter of its first copy" do
      let(:filters) { {matching_filters: {"region" => ["eu"]}} }

      before do
        ingest(ingested_at: period.watermark, region: "eu")
        ingest(ingested_at: period.watermark + 10.minutes, region: "us")
      end

      it { is_expected.to be(true) }
    end

    context "with an event ingested once by the watermark and enriched after it" do
      before { ingest(ingested_at: period.watermark, enriched_at: period.watermark + 1.second) }

      it { is_expected.to be(false) }
    end

    context "with an event first ingested after the watermark" do
      before { ingest(ingested_at: period.watermark + 10.minutes) }

      it { is_expected.to be(false) }
    end

    context "with an event ingested twice by the watermark" do
      before do
        ingest(ingested_at: period.watermark - 10.minutes)
        ingest(ingested_at: period.watermark)
      end

      it { is_expected.to be(false) }
    end

    context "with a copy ingested by the watermark for another subscription" do
      before do
        Clickhouse::EventsRaw.create!(
          organization_id: organization.id,
          external_customer_id: customer.external_id,
          external_subscription_id: "other-subscription",
          transaction_id:,
          timestamp:,
          code: billable_metric.code,
          properties: {"value" => "1"},
          ingested_at: period.watermark
        )
        ingest(ingested_at: period.watermark + 10.minutes)
      end

      it { is_expected.to be(false) }
    end
  end

  describe "string values containing a backslash or a quote" do
    subject(:event_store) do
      described_class.new(
        code: billable_metric.code,
        billing_context: Billing::Context.from(subscription:),
        boundaries:,
        filters:
      )
    end

    let(:billable_metric) { create(:sum_billable_metric, field_name: "value") }
    let(:organization) { billable_metric.organization }
    let(:customer) { create(:customer, organization:) }
    let(:subscription) { create(:subscription, customer:, started_at: DateTime.parse("2023-03-15")) }
    let(:boundaries) do
      {
        from_datetime: subscription.started_at.beginning_of_day,
        to_datetime: subscription.started_at.end_of_month.end_of_day,
        charges_duration: 31
      }
    end
    let(:filters) { {} }

    before do
      event_store.aggregation_property = billable_metric.field_name
      event_store.numeric_property = true

      create_event(timestamp: subscription.started_at + 1.day, value: 2, properties: {"a\\" => "back\\", "b'" => "quote'"})
      create_event(timestamp: subscription.started_at + 2.days, value: 3, properties: {"a\\" => "other"})
    end

    context "when the group keys end with a backslash or contain a quote" do
      let(:filters) { {grouped_by: ["a\\", "b'"]} }

      it "groups by the literal keys" do
        expect(event_store.grouped_sum).to match_array([
          Events::Stores::BaseStore::GroupedAggregationResult.new(groups: {"a\\" => "back\\", "b'" => "quote'"}, value: 2, events_count: 1),
          Events::Stores::BaseStore::GroupedAggregationResult.new(groups: {"a\\" => "other", "b'" => nil}, value: 3, events_count: 1)
        ])
      end
    end

    context "when a key that escapes its closing quote is followed by SQL" do
      let(:filters) { {grouped_by: ["a\\", ") AS g_0, (SELECT 'injected') AS g_1 FROM events_enriched) --"]} }

      it "treats the second key as a property name" do
        groups = event_store.grouped_sum.map(&:groups)

        expect(groups.flat_map(&:values)).not_to include("injected")
        expect(groups).to all(include(") AS g_0, (SELECT 'injected') AS g_1 FROM events_enriched) --" => nil))
      end
    end

    context "when the unique count property ends with a backslash" do
      before { event_store.aggregation_property = "a\\" }

      it "counts the literal property values" do
        expect(event_store.unique_count.value).to eq(2)
      end
    end

    context "when a weighted sum is grouped by a key ending with a backslash" do
      let(:filters) { {grouped_by: ["a\\"]} }

      it "groups by the literal key" do
        expect(event_store.grouped_weighted_sum.map(&:groups)).to match_array([{"a\\" => "back\\"}, {"a\\" => "other"}])
      end
    end

    context "when a grouped_by value ends with a backslash" do
      let(:filters) { {grouped_by_values: {"a\\" => "back\\"}} }

      it "matches the literal value" do
        expect(event_store.sum).to eq(Events::Stores::BaseStore::AggregationResult.new(value: 2, events_count: 1))
      end
    end

    context "when a matching filter value ends with a backslash" do
      let(:filters) { {matching_filters: {"a\\" => ["back\\"]}} }

      it "matches the literal value" do
        expect(event_store.count).to eq(Events::Stores::BaseStore::AggregationResult.new(value: 1, events_count: 1))
      end
    end

    context "when an ignored filter value ends with a backslash" do
      let(:filters) { {ignored_filters: [{"a\\" => ["back\\"]}]} }

      it "ignores the literal value" do
        expect(event_store.count).to eq(Events::Stores::BaseStore::AggregationResult.new(value: 1, events_count: 1))
      end
    end

    context "when the recurring sum reads the delta of a snapshot period" do
      let(:period) do
        RecurringAggregationSnapshots::FetchService::Period.new(to_datetime: subscription.started_at, watermark: Time.current)
      end

      context "with a grouped_by value ending with a backslash" do
        let(:filters) { {grouped_by_values: {"a\\" => "back\\"}} }

        it "matches the literal value" do
          expect(event_store.recurring_sum(watermark: Time.current, period:).value).to eq(2)
        end
      end

      context "with a matching filter value ending with a backslash" do
        let(:filters) { {matching_filters: {"a\\" => ["back\\"]}} }

        it "matches the literal value" do
          expect(event_store.recurring_sum(watermark: Time.current, period:).value).to eq(2)
        end
      end
    end
  end

  # Pins the query shape behind #count. Deduplication relies on the `FINAL`
  # modifier (ReplacingMergeTree collapses duplicated sorting keys at read time).
  # The unfiltered count queries the table directly; filtered counts go through
  # the events CTE so the filter is applied to the deduplicated rows.
  describe "#count_query" do
    subject(:event_store) do
      described_class.new(code: billable_metric.code, billing_context: Billing::Context.from(subscription:), boundaries:, filters:)
    end

    let(:billable_metric) { create(:sum_billable_metric, field_name: "value", code: "bm:code") }
    let(:organization) { billable_metric.organization }
    let(:charge) { create(:standard_charge, organization:, billable_metric:) }
    let(:customer) { create(:customer, organization:) }
    let(:subscription) { create(:subscription, customer:, started_at: DateTime.parse("2023-03-15")) }
    let(:boundaries) do
      {
        from_datetime: subscription.started_at.beginning_of_day,
        to_datetime: subscription.started_at.end_of_month.end_of_day,
        charges_duration: 31
      }
    end
    let(:filters) { {} }

    context "when unfiltered" do
      it "counts directly on the deduplicated table without a CTE" do
        sql = event_store.count_query

        expect(sql).not_to include("WITH")
        expect(sql).to include("FROM events_enriched FINAL")
      end
    end

    context "when grouped_by_values is set" do
      let(:filters) { {grouped_by_values: {"region" => "europe"}} }

      it "uses the CTE-based deduplication path" do
        sql = event_store.count_query

        expect(sql).to include("WITH")
        expect(sql).to include("FROM events_enriched FINAL")
      end
    end

    context "when matching_filters are set" do
      let(:filters) { {matching_filters: {"region" => ["europe"]}} }

      it "uses the CTE-based deduplication path" do
        sql = event_store.count_query

        expect(sql).to include("WITH")
        expect(sql).to include("FROM events_enriched FINAL")
      end
    end

    context "when ignored_filters are set" do
      let(:filters) { {ignored_filters: [{"region" => ["europe"]}]} }

      it "uses the CTE-based deduplication path" do
        sql = event_store.count_query

        expect(sql).to include("WITH")
        expect(sql).to include("FROM events_enriched FINAL")
      end
    end

    context "when grouped_by is set without grouped_by_values or filters" do
      let(:filters) { {grouped_by: ["region"]} }

      it "still uses the CTE-free fast path (grouped_by alone does not filter a count)" do
        expect(event_store.count_query).not_to include("WITH")
      end
    end

    context "when use_from_boundary is false" do
      it "omits the lower timestamp bound without injecting NULL" do
        event_store.use_from_boundary = false
        sql = event_store.count_query

        expect(sql).not_to include("WITH")
        expect(sql.upcase).not_to include("NULL")
        expect(sql).not_to include("timestamp >=")
        expect(sql).to include("timestamp <=")
      end
    end
  end

  # Real-data equivalence: the deduplicated + unfiltered #count uses the CTE-free
  # fast path. These assert it returns the SAME number as the CTE-based query on
  # identical data, across re-enrichment duplicates and boundary edges.
  describe "#count fast-path equivalence with the CTE-based query" do
    subject(:event_store) do
      described_class.new(code: billable_metric.code, billing_context: Billing::Context.from(subscription:), boundaries:, filters: {})
    end

    let(:billable_metric) { create(:sum_billable_metric, field_name: "value", code: "bm:code") }
    let(:organization) { billable_metric.organization }
    let(:charge) { create(:standard_charge, organization:, billable_metric:) }
    let(:customer) { create(:customer, organization:) }
    let(:subscription) { create(:subscription, customer:, started_at: DateTime.parse("2023-03-15")) }
    let(:boundaries) do
      {
        from_datetime: subscription.started_at.beginning_of_day,
        to_datetime: subscription.started_at.end_of_month.end_of_day,
        charges_duration: 31
      }
    end
    let(:ts) { subscription.started_at.beginning_of_day + 1.day }

    def insert_event(transaction_id:, timestamp:, enriched_at:, value: 1)
      Clickhouse::EventsEnriched.create!(
        transaction_id:,
        organization_id: organization.id,
        external_subscription_id: subscription.external_id,
        code: billable_metric.code,
        timestamp:,
        properties: {"value" => value},
        value:,
        decimal_value: value.to_d,
        precise_total_amount_cents: value,
        enriched_at:
      )
    end

    def cte_based_count
      sql = event_store.send(
        :with_ctes,
        event_store.events_cte_queries(deduplicated_columns: %w[value]),
        "SELECT count()\nFROM events"
      )
      Events::Stores::Utils::ClickhouseConnection.connection_with_retry { |c| c.select_value(sql).to_i }
    end

    it "collapses re-enrichment duplicates of the same dedup key into one" do
      txn = SecureRandom.uuid
      insert_event(transaction_id: txn, timestamp: ts, enriched_at: 2.minutes.ago)
      insert_event(transaction_id: txn, timestamp: ts, enriched_at: 1.minute.ago)
      insert_event(transaction_id: txn, timestamp: ts, enriched_at: Time.current)
      insert_event(transaction_id: SecureRandom.uuid, timestamp: ts + 1.day, enriched_at: Time.current)

      expect(event_store.count.value).to eq(2)
      expect(event_store.count.value).to eq(cte_based_count)
    end

    it "treats the same transaction_id at different timestamps as distinct events" do
      txn = SecureRandom.uuid
      insert_event(transaction_id: txn, timestamp: ts, enriched_at: Time.current)
      insert_event(transaction_id: txn, timestamp: ts + 1.hour, enriched_at: Time.current)

      expect(event_store.count.value).to eq(2)
      expect(event_store.count.value).to eq(cte_based_count)
    end

    it "excludes events outside the boundaries" do
      insert_event(transaction_id: SecureRandom.uuid, timestamp: ts, enriched_at: Time.current)
      insert_event(transaction_id: SecureRandom.uuid, timestamp: boundaries[:to_datetime] + 2.days, enriched_at: Time.current)

      expect(event_store.count.value).to eq(1)
      expect(event_store.count.value).to eq(cte_based_count)
    end

    it "returns zero when there are no events" do
      expect(event_store.count.value).to eq(0)
      expect(event_store.count.value).to eq(cte_based_count)
    end
  end

  # Events sharing the pay-in-advance boundary timestamp are tie-broken by
  # transaction_id so each gets a distinct position, not the batch's last unit.
  describe "#count with a pay-in-advance boundary" do
    let(:billable_metric) { create(:billable_metric, field_name: "value", code: "bm:code") }
    let(:organization) { billable_metric.organization }
    let(:charge) { create(:standard_charge, organization:, billable_metric:) }
    let(:customer) { create(:customer, organization:) }
    let(:subscription) { create(:subscription, customer:, started_at: DateTime.parse("2023-03-15")) }
    let(:boundary_timestamp) { subscription.started_at.beginning_of_day + 1.day }

    def event_store_for(boundary_transaction_id)
      described_class.new(
        code: billable_metric.code,
        billing_context: Billing::Context.from(subscription:),
        boundaries: {
          from_datetime: subscription.started_at.beginning_of_day,
          to_datetime: subscription.started_at.end_of_month.end_of_day,
          max_timestamp: boundary_timestamp,
          charges_duration: 31
        },
        filters: {
          event: Events::Common.new(
            organization_id: organization.id,
            external_subscription_id: subscription.external_id,
            transaction_id: boundary_transaction_id,
            code: billable_metric.code,
            timestamp: boundary_timestamp
          )
        }
      )
    end

    def insert_event(transaction_id:, timestamp:)
      Clickhouse::EventsEnriched.create!(
        transaction_id:,
        organization_id: organization.id,
        external_subscription_id: subscription.external_id,
        code: billable_metric.code,
        timestamp:,
        properties: {"value" => 1},
        value: 1,
        decimal_value: 1.to_d,
        precise_total_amount_cents: 1,
        enriched_at: Time.current
      )
    end

    before do
      insert_event(transaction_id: SecureRandom.uuid, timestamp: boundary_timestamp - 1.hour)
      insert_event(transaction_id: SecureRandom.uuid, timestamp: boundary_timestamp - 2.hours)
      %w[tx-1 tx-2 tx-3].each { |tx| insert_event(transaction_id: tx, timestamp: boundary_timestamp) }
    end

    it "assigns each event sharing the boundary timestamp a distinct position" do
      counts = %w[tx-1 tx-2 tx-3].map { |tx| event_store_for(tx).count.value }

      expect(counts).to eq([3, 4, 5])
    end
  end

  # ClickHouse rejects a query before running it when the statement is larger than
  # `max_query_size` (256 kB) or expands to more than `max_ast_elements` (50 000) nodes.
  # A charge carrying thousands of filters serializes into a predicate past both limits,
  # so the rejected query is replayed with them raised.
  describe "filters larger than the ClickHouse parser defaults" do
    subject(:event_store) do
      described_class.new(
        code: billable_metric.code,
        billing_context: Billing::Context.from(subscription:),
        boundaries:,
        filters: {ignored_filters:}
      )
    end

    let(:billable_metric) { create(:sum_billable_metric, field_name: "value", code: "bm:code") }
    let(:organization) { billable_metric.organization }
    let(:customer) { create(:customer, organization:) }
    let(:subscription) { create(:subscription, customer:, started_at: DateTime.parse("2023-03-15")) }
    let(:boundaries) do
      {
        from_datetime: subscription.started_at.beginning_of_day,
        to_datetime: subscription.started_at.end_of_month.end_of_day,
        charges_duration: 31
      }
    end
    let(:ignored_filters) do
      Array.new(2_000) do |index|
        {"model" => ["model-#{index}"], "type" => ["type-#{index}"], "zone" => ["zone-#{index}"]}
      end
    end

    before do
      create_event(timestamp: DateTime.parse("2023-03-16"), value: 10, properties: {"model" => "kept"})
    end

    it "exceeds both parser defaults" do
      sql = event_store.count_query

      expect(sql.size).to be > 262_144
    end

    it "aggregates instead of failing to parse" do
      expect(event_store.count).to eq(Events::Stores::BaseStore::AggregationResult.new(value: 1, events_count: 1))
    end
  end

  # decimal_value is a Decimal(38, 26), so a sum held in that type wraps above 2^127 / 10^26 (~1.70e12).
  describe "#sum above the Decimal128 limit" do
    subject(:event_store) do
      described_class.new(
        code: billable_metric.code,
        billing_context: Billing::Context.from(subscription:),
        boundaries:,
        filters: {}
      )
    end

    let(:billable_metric) { create(:sum_billable_metric, field_name: "value") }
    let(:organization) { billable_metric.organization }
    let(:customer) { create(:customer, organization:) }
    let(:subscription) { create(:subscription, customer:, started_at: DateTime.parse("2023-03-15")) }
    let(:boundaries) do
      {
        from_datetime: subscription.started_at.beginning_of_day,
        to_datetime: subscription.started_at.end_of_month.end_of_day,
        charges_duration: 31
      }
    end

    before do
      event_store.aggregation_property = billable_metric.field_name
      event_store.numeric_property = true

      250.times { create_event(timestamp: subscription.started_at + 1.day, value: 8_000_000_000) }
    end

    it "returns the exact total" do
      result = event_store.sum

      expect(result.value).to eq(BigDecimal("2000000000000")) # 250 events x 8e9
      expect(result.events_count).to eq(250)
    end
  end

  describe "other sums above the Decimal128 limit" do
    subject(:event_store) do
      described_class.new(
        code: billable_metric.code,
        billing_context: Billing::Context.from(subscription:),
        boundaries:,
        filters: {grouped_by:}
      )
    end

    let(:billable_metric) { create(:sum_billable_metric, field_name: "value") }
    let(:organization) { billable_metric.organization }
    let(:customer) { create(:customer, organization:) }
    let(:subscription) { create(:subscription, customer:, started_at: DateTime.parse("2023-03-15")) }
    let(:boundaries) do
      {
        from_datetime: subscription.started_at.beginning_of_day,
        to_datetime: subscription.started_at.end_of_month.end_of_day,
        charges_duration: 31
      }
    end
    let(:grouped_by) { nil }
    let(:events_count) { 250 }
    let(:event_value) { 8_000_000_000 }

    before do
      event_store.aggregation_property = billable_metric.field_name
      event_store.numeric_property = true

      insert_events(events_count, timestamp: subscription.started_at + 1.day, value: event_value, properties: {"region" => "europe"})
    end

    describe "#sum" do
      let(:events_count) { 570 }

      it "returns the exact total past twice the limit" do
        result = event_store.sum

        expect(result.value).to eq(BigDecimal("4560000000000")) # 570 events x 8e9
        expect(result.events_count).to eq(570)
      end
    end

    describe "#grouped_sum" do
      let(:grouped_by) { %w[region] }

      it "returns the exact total of the group" do
        expect(event_store.grouped_sum).to eq([
          Events::Stores::BaseStore::GroupedAggregationResult.new(
            groups: {"region" => "europe"},
            value: BigDecimal("2000000000000"), # 250 events x 8e9
            events_count: 250
          )
        ])
      end
    end

    describe "#recurring_sum" do
      it "returns the exact total and snapshot total" do
        expect(event_store.recurring_sum(watermark: Time.current + 1.hour)).to eq(
          Events::Stores::BaseStore::RecurringAggregationResult.new(
            value: BigDecimal("2000000000000"), # 250 events x 8e9
            snapshot_value: BigDecimal("2000000000000"), # all 250 events enriched before the watermark
            events_count: 250,
            snapshot_events_count: 250
          )
        )
      end
    end

    describe "#grouped_recurring_sum" do
      let(:grouped_by) { %w[region] }

      it "returns the exact total and snapshot total of the group" do
        expect(event_store.grouped_recurring_sum(watermark: Time.current + 1.hour)).to eq([
          Events::Stores::BaseStore::GroupedRecurringAggregationResult.new(
            groups: {"region" => "europe"},
            value: BigDecimal("2000000000000"), # 250 events x 8e9
            snapshot_value: BigDecimal("2000000000000"), # all 250 events enriched before the watermark
            events_count: 250,
            snapshot_events_count: 250
          )
        ])
      end
    end

    describe "#sum_date_breakdown" do
      it "returns the exact total of the day" do
        expect(event_store.sum_date_breakdown).to eq([
          {date: Date.new(2023, 3, 16), value: BigDecimal("2000000000000")} # 250 events x 8e9
        ])
      end
    end

    describe "#prorated_sum" do
      let(:events_count) { 500 }

      it "returns the exact total and prorated total" do
        result = event_store.prorated_sum(period_duration: 30, persisted_duration: 15)

        expect(result.value).to eq(BigDecimal("4000000000000")) # 500 events x 8e9
        expect(result.prorated_value).to be_within(0.01).of(2_000_000_000_000) # 4e12 x 15 / 30, Float64 ratio product
        expect(result.events_count).to eq(500)
      end

      it "returns the exact total and prorates each event over its remaining days" do
        result = event_store.prorated_sum(period_duration: 31)

        expect(result.value).to eq(BigDecimal("4000000000000")) # 500 events x 8e9
        expect(result.prorated_value).to be_within(0.01).of(4_000_000_000_000 * 16.fdiv(31)) # 16 to 31 March, 16 of 31 days
      end

      context "with a ratio whose decimal text rounds up" do
        let(:events_count) { 1 }
        let(:event_value) { 31 }

        it "keeps the prorated value at or below the exact product" do
          result = event_store.prorated_sum(period_duration: 31, persisted_duration: 15)

          expect(result.prorated_value.ceil(5)).to eq(15) # 31 x 15 / 31
        end
      end
    end

    describe "#grouped_prorated_sum" do
      let(:events_count) { 500 }
      let(:grouped_by) { %w[region] }

      it "returns the exact total and prorated total of the group" do
        result = event_store.grouped_prorated_sum(period_duration: 30, persisted_duration: 15)

        expect(result.map(&:groups)).to eq([{"region" => "europe"}])
        expect(result.first.value).to eq(BigDecimal("4000000000000")) # 500 events x 8e9
        expect(result.first.prorated_value).to be_within(0.01).of(2_000_000_000_000) # 4e12 x 15 / 30, Float64 ratio product
        expect(result.first.events_count).to eq(500)
      end
    end
  end

  # Events from the API keep their JSON types, while events_enriched stores every property as text.
  describe "#active_unique_property? with a numeric property" do
    subject(:event_store) do
      described_class.new(
        code: billable_metric.code,
        billing_context: Billing::Context.from(subscription:),
        boundaries: {from_datetime: subscription.started_at, to_datetime: subscription.started_at + 1.month}
      )
    end

    let(:billable_metric) { create(:unique_count_billable_metric, field_name: "user_id") }
    let(:organization) { billable_metric.organization }
    let(:customer) { create(:customer, organization:) }
    let(:subscription) { create(:subscription, customer:, started_at: Time.zone.parse("2026-10-01")) }
    let(:event) do
      Events::Common.new(
        organization_id: organization.id,
        transaction_id: SecureRandom.uuid,
        external_subscription_id: subscription.external_id,
        code: billable_metric.code,
        timestamp: subscription.started_at + 2.days,
        properties: {"user_id" => 1}
      )
    end

    before do
      event_store.aggregation_property = "user_id"
      create_event(timestamp: subscription.started_at + 1.day, value: "1")
    end

    it "matches an earlier event storing the same value as text" do
      expect(event_store).to be_active_unique_property(event)
    end
  end
end
