# frozen_string_literal: true

module Clickhouse
  class EventsRaw < BaseRecord
    self.table_name = 'events_raw'
  end
end

# == Schema Information
#
# Table name: events_raw
#
#  code                       :string           not null, primary key
#  precise_total_amount_cents :decimal(40, 15)
#  properties                 :string           not null
#  timestamp                  :datetime         not null, primary key
#  external_customer_id       :string           not null
#  external_subscription_id   :string           not null, primary key
#  organization_id            :string           not null, primary key
#  transaction_id             :string           not null, primary key
#
