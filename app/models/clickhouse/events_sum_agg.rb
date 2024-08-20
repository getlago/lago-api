# frozen_string_literal: true

module Clickhouse
  class EventsSumAgg < BaseRecord
    self.table_name = 'events_sum_agg'
  end
end

# == Schema Information
#
# Table name: events_sum_agg
#
#  code                     :string           not null
#  filters                  :string           not null
#  grouped_by               :string           not null
#  timestamp                :datetime         not null
#  value                    :decimal(26, )
#  charge_id                :string           not null
#  external_subscription_id :string           not null
#  organization_id          :string           not null
#
