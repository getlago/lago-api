# frozen_string_literal: true

module Clickhouse
  class EventsAggregated < BaseRecord
    self.table_name = "events_aggregated"

    def readonly?
      true
    end
  end
end

# == Schema Information
#
# Table name: events_aggregated
#
#  aggregated_at                        :datetime         not null
#  code                                 :string           not null, primary key
#  count_state                          :integer          not null
#  grouped_by                           :string           not null, primary key
#  latest_state                         :decimal(38, )    not null
#  max_state                            :decimal(38, 26)  not null
#  precise_total_amount_cents_sum_state :decimal(40, 15)  not null
#  started_at                           :datetime         not null, primary key
#  sum_state                            :decimal(38, 26)  not null
#  charge_filter_id                     :string           default(""), not null, primary key
#  charge_id                            :string           not null, primary key
#  external_subscription_id             :string           not null, primary key
#  organization_id                      :string           not null, primary key
#  plan_id                              :string           not null
#  subscription_id                      :string           not null, primary key
#
