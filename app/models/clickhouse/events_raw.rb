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
#  code                     :string           not null
#  properties               :map              not null
#  timestamp                :datetime         not null
#  external_customer_id     :string           not null
#  external_subscription_id :string           not null
#  organization_id          :string           not null
#  transaction_id           :string           not null
#
