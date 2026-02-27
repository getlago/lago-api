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
    it_behaves_like "an event store", with_event_duplication: false,
      excluding_features: %i[
        events
      ]
  end

  context "with deduplication" do
    it_behaves_like "an event store", with_event_duplication: true,
      excluding_features: %i[
        events
      ]
  end
end
