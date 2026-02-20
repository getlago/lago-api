# frozen_string_literal: true

require "rails_helper"

require_relative "shared_examples/an_event_store"

RSpec.describe Events::Stores::ClickhouseEnrichedStore, clickhouse: {clean_before: true} do
  def create_event(timestamp:, value:, properties: {}, grouped_by: {}, transaction_id: SecureRandom.uuid, code: billable_metric.code, charge_filter: nil)
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
      grouped_by: grouped_by.transform_values { it || "" },
      value:,
      decimal_value: value&.to_i&.to_d,
      precise_total_amount_cents: nil
    )
  end

  alias_method :create_enriched_event, :create_event

  context "without deduplication" do
    it_behaves_like "an event store", with_event_duplication: false
  end

  context "with deduplication" do
    it_behaves_like "an event store", with_event_duplication: true
  end
end
