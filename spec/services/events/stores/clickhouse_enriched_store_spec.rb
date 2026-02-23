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
      charge_filter_id: charge_filter&.id,
      charge_filter_version: charge_filter&.updated_at,
      timestamp:,
      properties:,
      grouped_by: grouped_values,
      value:,
      decimal_value: value&.to_i&.to_d,
      precise_total_amount_cents: nil,
      enriched_at:
    )
  end

  alias_method :create_enriched_event, :create_event

  context "without deduplication" do
    it_behaves_like "an event store", with_event_duplication: false,
      excluding_features: %i[
        events
        events_values
        last_event
        grouped_last_event
        prorated_events_values
        distinct_codes
        distinct_charges_and_filters
        active_unique_property?
        unique_count
        grouped_unique_count
        sum
        sum_date_breakdown
        grouped_sum
        sum_precise_total_amount_cents
        grouped_sum_precise_total_amount_cents
        prorated_sum
        grouped_prorated_sum
        weighted_sum
        weighted_sum_breakdown
        grouped_weighted_sum
      ]
  end

  context "with deduplication" do
    it_behaves_like "an event store", with_event_duplication: true,
      excluding_features: %i[
        events
        events_values
        last_event
        grouped_last_event
        distinct_codes
        distinct_charges_and_filters
        prorated_events_values
        active_unique_property?
        grouped_last
        unique_count
        grouped_unique_count
        sum
        sum_date_breakdown
        grouped_sum
        sum_precise_total_amount_cents
        grouped_sum_precise_total_amount_cents
        prorated_sum
        grouped_prorated_sum
        weighted_sum
        weighted_sum_breakdown
        grouped_weighted_sum
      ]
  end
end
