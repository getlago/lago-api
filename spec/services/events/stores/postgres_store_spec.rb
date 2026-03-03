# frozen_string_literal: true

require "rails_helper"

require_relative "shared_examples/an_event_store"

RSpec.describe Events::Stores::PostgresStore do
  it_behaves_like "an event store", with_event_duplication: false do
    def create_event(timestamp:, value:, properties: {}, transaction_id: SecureRandom.uuid, code: billable_metric.code, charge_filter: nil, enriched_at: nil)
      create(
        :event,
        transaction_id: transaction_id,
        organization_id: organization.id,
        external_subscription_id: subscription.external_id,
        external_customer_id: customer.external_id,
        code:,
        timestamp: timestamp,
        properties: properties.merge(billable_metric.field_name => value),
        precise_total_amount_cents: value
      )
    end

    def create_enriched_event(timestamp:, value:, properties: {}, transaction_id: SecureRandom.uuid, code: billable_metric.code, charge_filter: nil, enriched_at: nil)
      event = create(
        :event,
        transaction_id:,
        organization_id: organization.id,
        external_subscription_id: subscription.external_id,
        external_customer_id: customer.external_id,
        code:,
        timestamp:,
        properties:
      )

      create(
        :enriched_event,
        subscription:,
        event:,
        charge:,
        charge_filter_id: charge_filter&.id,
        value:,
        decimal_value: value&.to_i&.to_d
      )
    end

    def format_timestamp(timestamp, precision: nil)
      Time.zone.parse(timestamp)
    end
  end
end
