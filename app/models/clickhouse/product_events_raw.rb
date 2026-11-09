# frozen_string_literal: true

module Clickhouse
  class ProductEventsRaw < BaseRecord
    self.table_name = "product_events_raw"
    self.primary_key = nil

    # Events::CreateService stores the contract of a v2 event under external_subscription_id,
    # and the GraphQL Event type reads it there, for both event stores.
    alias_attribute :external_subscription_id, :external_contract_id

    delegate :customer, :customer_id, to: :contract, allow_nil: true

    def id
      "#{organization_id}-#{external_contract_id}-#{transaction_id}-#{ingested_at.to_i}"
    end

    def created_at
      ingested_at
    end

    def billable_metric
      BillableMetric.find_by(code:, organization_id:)
    end

    def api_client
    end

    def ip_address
    end

    def contract
      Contract
        .where(organization_id:, external_id: external_contract_id)
        .where.not(status: :canceled)
        .where(started_at: ..timestamp)
        .order(started_at: :desc)
        .first
    end

    # A product event belongs to a contract, never to a subscription.
    def subscription_id
    end

    def organization
      Organization.find_by(id: organization_id)
    end
  end
end

# == Schema Information
#
# Table name: product_events_raw
# Database name: clickhouse
#
#  code                       :string           not null
#  ingested_at                :datetime         not null
#  precise_total_amount_cents :decimal(40, 15)
#  properties                 :string           not null
#  timestamp                  :datetime         not null
#  external_contract_id       :string           not null
#  external_customer_id       :string           not null
#  organization_id            :string           not null
#  transaction_id             :string           not null
#
