# frozen_string_literal: true

require "rails_helper"

require_relative "shared_examples/an_event_store"

RSpec.describe Events::Stores::ClickhouseEnrichedStore, clickhouse: {clean_before: true} do
  def create_event(timestamp:, value:, properties: {}, transaction_id: SecureRandom.uuid, code: billable_metric.code, charge_filter: nil, enriched_at: nil, event_charge: nil, created_at: nil)
    effective_charge = event_charge || charge

    grouped_values = if events_grouped_by.present?
      events_grouped_by.index_with({}) { properties[it] || "" }
    end

    Clickhouse::EventsEnrichedExpanded.create!(
      transaction_id:,
      organization_id: organization.id,
      external_subscription_id: subscription.external_id,
      subscription_id: subscription.id,
      plan_id: subscription.plan_id,
      code:,
      aggregation_type: billable_metric.aggregation_type,
      charge_id: effective_charge.id,
      charge_version: effective_charge.updated_at,
      charge_filter_id: charge_filter&.id || "",
      charge_filter_version: charge_filter&.updated_at,
      timestamp:,
      properties: properties.merge(billable_metric.field_name => value).compact,
      grouped_by: grouped_values,
      value:,
      decimal_value: value&.to_i&.to_d,
      precise_total_amount_cents: value,
      enriched_at: created_at || enriched_at
    )
  end

  alias_method :create_enriched_event, :create_event

  def format_timestamp(timestamp, precision: 3)
    Time.zone.parse(timestamp).strftime("%Y-%m-%d %H:%M:%S.%#{precision}L")
  end

  context "without deduplication" do
    it_behaves_like "an event store", with_event_duplication: false, excluding_features: [:distinct_codes_and_property_combinations]
  end

  context "with deduplication" do
    it_behaves_like "an event store", with_event_duplication: true, excluding_features: [:distinct_codes_and_property_combinations]
  end

  describe "#grouped_arel_columns" do
    subject(:event_store) do
      described_class.new(
        code: billable_metric.code,
        subscription:,
        boundaries:,
        filters: {
          grouped_by:,
          presentation_by:
        }
      )
    end

    let(:billable_metric) { create(:sum_billable_metric, field_name: "value", code: "bm:code") }
    let(:organization) { billable_metric.organization }
    let(:customer) { create(:customer, organization:) }
    let(:subscription) { create(:subscription, customer:) }
    let(:boundaries) do
      {
        from_datetime: subscription.started_at.beginning_of_day,
        to_datetime: subscription.started_at.end_of_month.end_of_day,
        charges_duration: 31
      }
    end

    context "when presentation_by is not included in grouped_by" do
      let(:grouped_by) { ["cloud"] }
      let(:presentation_by) { ["agent_name"] }

      it "returns the precomputed sorted grouped by column" do
        columns, names = event_store.grouped_arel_columns

        expect(columns.count).to eq(1)
        expect(columns.first.left.name).to eq("sorted_grouped_by")
        expect(columns.first.right).to eq("grouped_by")
        expect(names).to eq(["grouped_by"])
      end
    end

    context "when presentation_by is included in grouped_by" do
      let(:grouped_by) { ["cloud", "agent_name"] }
      let(:presentation_by) { ["cloud"] }

      it "returns a mapped grouped_by from the grouped properties" do
        columns, names = event_store.grouped_arel_columns

        expect(columns.count).to eq(1)
        expect(columns.first.left.to_s).to eq("map('agent_name', sorted_properties['agent_name'], 'cloud', sorted_properties['cloud'])")
        expect(columns.first.right.to_s).to eq("grouped_by")
        expect(names).to eq(["grouped_by"])
      end
    end

    context "when the store is duplicated with another grouped_by" do
      let(:grouped_by) { ["cloud"] }
      let(:presentation_by) { ["agent_name"] }

      it "builds the mapped grouped_by from the duplicated grouped_by" do
        duplicated_store = event_store.dup
        duplicated_store.grouped_by = ["agent_name", "cloud"]

        columns, names = duplicated_store.grouped_arel_columns

        expect(event_store.grouped_by).to eq(["cloud"])
        expect(columns.count).to eq(1)
        expect(columns.first.left.to_s).to eq("map('agent_name', sorted_properties['agent_name'], 'cloud', sorted_properties['cloud'])")
        expect(columns.first.right.to_s).to eq("grouped_by")
        expect(names).to eq(["grouped_by"])
      end
    end
  end

  # A recurring metric (use_from_boundary false) always needs the code-based fallback so that
  # events predating subscription.started_at are aggregated, even when the subscription has no
  # previous_subscription_id link (e.g. a subscription sharing the same external_id was terminated
  # and recreated). Without the fallback, such pre-start events carry an earlier charge_id and are
  # dropped by the charge_id based query.
  describe "#needs_code_based_fallback? for recurring metrics" do
    let(:billable_metric) { create(:billable_metric, field_name: "seats", code: "seats") }
    let(:organization) { billable_metric.organization }
    let(:charge) { create(:standard_charge, organization:, billable_metric:) }
    let(:customer) { create(:customer, organization:) }
    # No previous_subscription_id link, even though earlier subscriptions shared the external_id.
    let(:subscription) do
      create(:subscription, customer:, external_id: "seat_sub", started_at: DateTime.parse("2023-03-01"))
    end
    let(:boundaries) do
      {
        from_datetime: subscription.started_at.beginning_of_day,
        to_datetime: subscription.started_at.end_of_month.end_of_day,
        charges_duration: 31
      }
    end

    subject(:event_store) do
      store = described_class.new(
        code: billable_metric.code,
        subscription:,
        boundaries:,
        filters: {charge_id: charge.id}
      )
      store.use_from_boundary = false # recurring metric
      store
    end

    it "runs the code-based fallback even without a previous subscription" do
      expect(subscription.previous_subscription_id).to be_nil
      expect(event_store.needs_code_based_fallback?(force_from: false)).to be(true)
    end

    context "when the metric is not recurring (use_from_boundary true)" do
      it "does not run the code-based fallback" do
        event_store.use_from_boundary = true
        expect(event_store.needs_code_based_fallback?(force_from: false)).to be(false)
      end
    end
  end

  # Behavioural scenarios for a recurring metric (seats) whose events may predate the current
  # subscription. These exercise the full ClickHouse aggregation path, so they must run against a
  # ClickHouse instance (`lago exec api bundle exec rspec`).
  describe "recurring aggregation of events before subscription.started_at" do
    let(:billable_metric) { create(:billable_metric, field_name: "seats", code: "seats") }
    let(:organization) { billable_metric.organization }
    let(:charge) { create(:standard_charge, organization:, billable_metric:) }
    let(:customer) { create(:customer, organization:) }
    let(:external_id) { "seat_sub" }
    let(:events_grouped_by) { nil }

    def build_store(sub, boundaries)
      store = described_class.new(
        code: billable_metric.code,
        subscription: sub,
        boundaries:,
        filters: {charge_id: charge.id}
      )
      store.use_from_boundary = false # recurring metric
      store
    end

    # Scenario 1: monthly subscriptions sharing the same external_id, each with its own started_at,
    # NOT linked through previous_subscription_id (terminated and recreated). A seat received during
    # the first month was enriched under that month's charge, so it carries a different charge_id
    # than the current subscription. It must still be aggregated for the current subscription via
    # the code-based fallback.
    context "when each subscription keeps its own started_at and is not linked" do
      let(:january_charge) { create(:standard_charge, organization:, billable_metric:, plan: create(:plan, organization:)) }
      let!(:subscription) do
        create(:subscription, customer:, external_id:, started_at: DateTime.parse("2023-03-01"))
      end

      let(:boundaries) do
        {
          from_datetime: DateTime.parse("2023-03-01").beginning_of_day,
          to_datetime: DateTime.parse("2023-03-31").end_of_day,
          charges_duration: 31
        }
      end

      before do
        # Seat received in January, before the current subscription started, enriched under the
        # January subscription's (different) charge.
        create_event(timestamp: DateTime.parse("2023-01-15"), value: 1, transaction_id: SecureRandom.uuid, event_charge: january_charge)
        # Seat received during the current period, under the current charge.
        create_event(timestamp: DateTime.parse("2023-03-10"), value: 1, transaction_id: SecureRandom.uuid)
      end

      it "aggregates the pre-start seat (different charge_id) together with the current-period seat" do
        expect(build_store(subscription, boundaries).count.events_count).to eq(2)
      end
    end

    # Scenario 2: the current subscription inherits the started_at of the first one (January 1st),
    # so a January seat is after started_at and aggregated through the regular charge_id query.
    context "when the subscription inherits the first started_at" do
      let!(:subscription) do
        create(:subscription, customer:, external_id:, started_at: DateTime.parse("2023-01-01"))
      end

      let(:boundaries) do
        {
          from_datetime: DateTime.parse("2023-01-01").beginning_of_day,
          to_datetime: DateTime.parse("2023-03-31").end_of_day,
          charges_duration: 90
        }
      end

      before do
        create_event(timestamp: DateTime.parse("2023-01-15"), value: 1, transaction_id: SecureRandom.uuid)
        create_event(timestamp: DateTime.parse("2023-03-10"), value: 1, transaction_id: SecureRandom.uuid)
      end

      it "aggregates every seat" do
        expect(build_store(subscription, boundaries).count.events_count).to eq(2)
      end
    end

    # Scenario 3: a single subscription started on June 1st with events during June. Events after the
    # subscription start are aggregated as usual.
    context "when a single subscription receives events after it started" do
      let!(:subscription) do
        create(:subscription, customer:, external_id:, started_at: DateTime.parse("2023-06-01"))
      end

      let(:boundaries) do
        {
          from_datetime: DateTime.parse("2023-06-01").beginning_of_day,
          to_datetime: DateTime.parse("2023-06-30").end_of_day,
          charges_duration: 30
        }
      end

      before do
        create_event(timestamp: DateTime.parse("2023-06-05"), value: 1, transaction_id: SecureRandom.uuid)
        create_event(timestamp: DateTime.parse("2023-06-20"), value: 1, transaction_id: SecureRandom.uuid)
      end

      it "aggregates the June seats" do
        expect(build_store(subscription, boundaries).count.events_count).to eq(2)
      end
    end
  end

  # SQL-shape guard: the transaction_id tie-break applies only when aggregating for a
  # pay-in-advance event AND the boundary is that event's own timestamp.
  describe "#charge_id_based_where_sql boundary predicate" do
    let(:billable_metric) { create(:billable_metric, field_name: "value", code: "bm:code") }
    let(:organization) { billable_metric.organization }
    let(:charge) { create(:standard_charge, organization:, billable_metric:) }
    let(:customer) { create(:customer, organization:) }
    let(:subscription) { create(:subscription, customer:, started_at: DateTime.parse("2023-03-15")) }
    let(:event_timestamp) { subscription.started_at.beginning_of_day + 1.day }

    def event_store(filters)
      described_class.new(
        code: billable_metric.code,
        subscription:,
        boundaries: {
          from_datetime: subscription.started_at.beginning_of_day,
          to_datetime: subscription.started_at.end_of_month.end_of_day,
          max_timestamp: event_timestamp,
          charges_duration: 31
        },
        filters: {charge_id: charge.id}.merge(filters)
      )
    end

    it "tie-breaks the boundary on transaction_id for a pay-in-advance event" do
      store = event_store(event: Events::Common.new(transaction_id: "tx-boundary", timestamp: event_timestamp))

      sql = store.charge_id_based_where_sql(from_datetime: nil, to_datetime: event_timestamp)

      expect(sql).to include("transaction_id <= 'tx-boundary'")
    end

    it "keeps the plain timestamp upper bound without a pay-in-advance event" do
      store = event_store({})

      sql = store.charge_id_based_where_sql(from_datetime: nil, to_datetime: event_timestamp)

      expect(sql).to include("timestamp <=")
      expect(sql).not_to include("transaction_id <=")
    end

    it "keeps the plain timestamp upper bound when the boundary is not the event timestamp" do
      store = event_store(event: Events::Common.new(transaction_id: "tx-boundary", timestamp: event_timestamp))

      sql = store.charge_id_based_where_sql(from_datetime: nil, to_datetime: event_timestamp - 0.001.seconds)

      expect(sql).to include("timestamp <=")
      expect(sql).not_to include("transaction_id <=")
    end
  end
end
