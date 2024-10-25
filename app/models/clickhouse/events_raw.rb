# frozen_string_literal: true

module Clickhouse
  class EventsRaw < BaseRecord
    self.table_name = 'events_raw'

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

    def subscription
      organization.subscriptions.find_by(external_id: external_subscription_id)
    end

    def customer_timezone
    end

    def organization
      Organization.find_by(id: organization_id)
    end

    private

    delegate :customer, to: :subscription
  end
end

# == Schema Information
#
# Table name: events_raw
#
#  code                       :string           not null, primary key
#  ingested_at                :datetime         not null
#  precise_total_amount_cents :decimal(40, 15)
#  properties                 :string           not null
#  timestamp                  :datetime         not null, primary key
#  external_customer_id       :string           not null
#  external_subscription_id   :string           not null, primary key
#  organization_id            :string           not null, primary key
#  transaction_id             :string           not null, primary key
#
