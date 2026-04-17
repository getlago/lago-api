# frozen_string_literal: true

require "rails_helper"

require_relative "shared_examples/an_event_store"

RSpec.describe Events::Stores::ClickhouseStore, clickhouse: {clean_before: true} do
  def create_event(timestamp:, value:, properties: {}, transaction_id: SecureRandom.uuid, code: billable_metric.code, charge_filter: nil, enriched_at: nil, event_charge: nil)
    Clickhouse::EventsEnriched.create!(
      transaction_id: transaction_id,
      organization_id: organization.id,
      external_subscription_id: subscription.external_id,
      code:,
      timestamp: timestamp,
      properties: properties.merge(billable_metric.field_name => value).compact,
      value: value,
      decimal_value: value&.to_i&.to_d,
      precise_total_amount_cents: value,
      enriched_at: Time.current
    )
  end

  def create_enriched_event(timestamp:, value:, properties: {}, transaction_id: SecureRandom.uuid, code: billable_metric.code, charge_filter: nil, enriched_at: nil)
    Clickhouse::EventsEnrichedExpanded.create!(
      transaction_id:,
      organization_id: organization.id,
      external_subscription_id: subscription.external_id,
      subscription_id: subscription.id,
      plan_id: subscription.plan_id,
      code:,
      aggregation_type: billable_metric.aggregation_type,
      charge_id: charge.id,
      charge_version: charge.updated_at,
      charge_filter_id: charge_filter&.id,
      charge_filter_version: charge_filter&.updated_at,
      timestamp:,
      properties:,
      value:,
      decimal_value: value&.to_i&.to_d,
      precise_total_amount_cents: nil
    )
  end

  def format_timestamp(timestamp, precision: 3)
    Time.zone.parse(timestamp).strftime("%Y-%m-%d %H:%M:%S.%#{precision}L")
  end

  context "without deduplication" do
    it_behaves_like "an event store", with_event_duplication: false
  end

  context "with deduplication" do
    it_behaves_like "an event store"

    # Regression test for https://github.com/getlago/lago-api/pull/5359
    #
    # Two rows share the same (transaction_id, timestamp) but carry different
    # filterable properties. Deduplication via argMax(enriched_at) must resolve
    # to a single row FIRST — otherwise the same logical event could be counted
    # in multiple filter/group buckets (once per property value it ever had).
    describe "filters applied after deduplication" do
      subject(:event_store) do
        described_class.new(
          code: billable_metric.code,
          subscription:,
          boundaries:,
          filters: {
            grouped_by: nil,
            grouped_by_values: nil,
            matching_filters: matching_filters,
            ignored_filters: [],
            charge_id: charge.id,
            charge_filter: nil
          },
          deduplicate: true
        )
      end

      let(:billable_metric) { create(:billable_metric, field_name: "value", code: "bm:code") }
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
          expect(event_store.count).to eq(0)
        end
      end

      context "when the filter matches only the latest property value" do
        let(:matching_filters) { {"region" => ["asia"]} }

        it "counts the deduplicated event exactly once" do
          expect(event_store.count).to eq(1)
        end
      end
    end
  end
end
