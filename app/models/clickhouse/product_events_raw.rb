# frozen_string_literal: true

module Clickhouse
  class ProductEventsRaw < BaseRecord
    self.table_name = "product_events_raw"
    self.primary_key = nil
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
#  external_customer_id       :string           not null
#  external_subscription_id   :string           not null
#  organization_id            :string           not null
#  transaction_id             :string           not null
#
