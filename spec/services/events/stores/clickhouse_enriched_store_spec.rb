# frozen_string_literal: true

require "rails_helper"

require_relative "shared_examples/an_event_store"

RSpec.describe Events::Stores::ClickhouseEnrichedStore, clickhouse: {clean_before: true} do
  def create_event(timestamp:, value:, properties: {}, transaction_id: SecureRandom.uuid, code: billable_metric.code, charge_filter: nil, enriched_at: nil)
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
      charge_id: charge.id,
      charge_version: charge.updated_at,
      charge_filter_id: charge_filter&.id || "",
      charge_filter_version: charge_filter&.updated_at,
      timestamp:,
      properties: properties.merge(billable_metric.field_name => value).compact,
      grouped_by: grouped_values,
      value:,
      decimal_value: value&.to_i&.to_d,
      precise_total_amount_cents: value,
      enriched_at:
    )
  end

  alias_method :create_enriched_event, :create_event

  def format_timestamp(timestamp, precision: 3)
    Time.zone.parse(timestamp).strftime("%Y-%m-%d %H:%M:%S.%#{precision}L")
  end

  context "without deduplication" do
    it_behaves_like "an event store", with_event_duplication: false
  end

  context "with deduplication" do
    it_behaves_like "an event store", with_event_duplication: true
  end

  describe "with previous_charge_ids" do
    let(:billable_metric) { create(:billable_metric, field_name: "value") }
    let(:organization) { billable_metric.organization }
    let(:customer) { create(:customer, organization:) }
    let(:subscription) { create(:subscription, customer:, started_at: DateTime.parse("2023-03-15")) }
    let(:charge) { create(:standard_charge, organization:, billable_metric:) }
    let(:previous_charge) { create(:standard_charge, organization:, billable_metric:) }
    let(:boundaries) do
      {
        from_datetime: subscription.started_at.beginning_of_day,
        to_datetime: subscription.started_at.end_of_month.end_of_day,
        charges_duration: 31
      }
    end

    let(:event_store) do
      described_class.new(
        code: billable_metric.code,
        subscription:,
        boundaries:,
        filters: {
          charge_id: charge.id,
          charge_filter: nil,
          previous_charge_ids: [previous_charge.id],
          previous_charge_filter_ids: []
        }
      )
    end

    before do
      Clickhouse::EventsEnrichedExpanded.create!(
        transaction_id: SecureRandom.uuid,
        organization_id: organization.id,
        external_subscription_id: subscription.external_id,
        subscription_id: subscription.id,
        plan_id: subscription.plan_id,
        code: billable_metric.code,
        aggregation_type: billable_metric.aggregation_type,
        charge_id: charge.id,
        charge_version: charge.updated_at,
        charge_filter_id: "",
        timestamp: boundaries[:from_datetime] + 1.day,
        value: "5",
        decimal_value: 5.to_d,
        precise_total_amount_cents: "5"
      )

      Clickhouse::EventsEnrichedExpanded.create!(
        transaction_id: SecureRandom.uuid,
        organization_id: organization.id,
        external_subscription_id: subscription.external_id,
        subscription_id: subscription.id,
        plan_id: subscription.plan_id,
        code: billable_metric.code,
        aggregation_type: billable_metric.aggregation_type,
        charge_id: previous_charge.id,
        charge_version: previous_charge.updated_at,
        charge_filter_id: "",
        timestamp: boundaries[:from_datetime] + 2.days,
        value: "3",
        decimal_value: 3.to_d,
        precise_total_amount_cents: "3"
      )
    end

    it "includes events from both current and previous charges" do
      expect(event_store.count).to eq(2)
      expect(event_store.sum).to eq(8)
    end

    context "without previous_charge_ids" do
      let(:event_store) do
        described_class.new(
          code: billable_metric.code,
          subscription:,
          boundaries:,
          filters: {
            charge_id: charge.id,
            charge_filter: nil
          }
        )
      end

      it "only includes events from the current charge" do
        expect(event_store.count).to eq(1)
        expect(event_store.sum).to eq(5)
      end
    end
  end

  describe "with previous_charge_filter_ids" do
    let(:billable_metric) { create(:billable_metric, field_name: "value") }
    let(:organization) { billable_metric.organization }
    let(:customer) { create(:customer, organization:) }
    let(:subscription) { create(:subscription, customer:, started_at: DateTime.parse("2023-03-15")) }
    let(:charge) { create(:standard_charge, organization:, billable_metric:) }
    let(:charge_filter) { create(:charge_filter, charge:) }
    let(:previous_charge_filter) { create(:charge_filter, charge:) }
    let(:boundaries) do
      {
        from_datetime: subscription.started_at.beginning_of_day,
        to_datetime: subscription.started_at.end_of_month.end_of_day,
        charges_duration: 31
      }
    end

    let(:event_store) do
      described_class.new(
        code: billable_metric.code,
        subscription:,
        boundaries:,
        filters: {
          charge_id: charge.id,
          charge_filter: charge_filter,
          previous_charge_ids: [],
          previous_charge_filter_ids: [previous_charge_filter.id]
        }
      )
    end

    before do
      Clickhouse::EventsEnrichedExpanded.create!(
        transaction_id: SecureRandom.uuid,
        organization_id: organization.id,
        external_subscription_id: subscription.external_id,
        subscription_id: subscription.id,
        plan_id: subscription.plan_id,
        code: billable_metric.code,
        aggregation_type: billable_metric.aggregation_type,
        charge_id: charge.id,
        charge_version: charge.updated_at,
        charge_filter_id: charge_filter.id,
        charge_filter_version: charge_filter.updated_at,
        timestamp: boundaries[:from_datetime] + 1.day,
        value: "5",
        decimal_value: 5.to_d,
        precise_total_amount_cents: "5"
      )

      Clickhouse::EventsEnrichedExpanded.create!(
        transaction_id: SecureRandom.uuid,
        organization_id: organization.id,
        external_subscription_id: subscription.external_id,
        subscription_id: subscription.id,
        plan_id: subscription.plan_id,
        code: billable_metric.code,
        aggregation_type: billable_metric.aggregation_type,
        charge_id: charge.id,
        charge_version: charge.updated_at,
        charge_filter_id: previous_charge_filter.id,
        charge_filter_version: previous_charge_filter.updated_at,
        timestamp: boundaries[:from_datetime] + 2.days,
        value: "3",
        decimal_value: 3.to_d,
        precise_total_amount_cents: "3"
      )
    end

    it "includes events from both current and previous charge filters" do
      expect(event_store.count).to eq(2)
      expect(event_store.sum).to eq(8)
    end

    context "without previous_charge_filter_ids" do
      let(:event_store) do
        described_class.new(
          code: billable_metric.code,
          subscription:,
          boundaries:,
          filters: {
            charge_id: charge.id,
            charge_filter: charge_filter
          }
        )
      end

      it "only includes events from the current charge filter" do
        expect(event_store.count).to eq(1)
        expect(event_store.sum).to eq(5)
      end
    end
  end
end
