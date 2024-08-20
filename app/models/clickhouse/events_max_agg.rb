# frozen_string_literal: true

module Clickhouse
  class EventsMaxAgg < BaseRecord
    self.table_name = 'events_max_agg'
  end
end

# == Schema Information
#
# Table name: events_max_agg
#
#  code                     :string           not null
#  filters                  :string           not null
#  grouped_by               :string           not null
#  timestamp                :datetime         not null
#  value                    :decimal(38, 26)  not null
#  charge_id                :string           not null
#  external_subscription_id :string           not null
#  organization_id          :string           not null
#
