# frozen_string_literal: true

module Clickhouse
  class EventsEnriched < BaseRecord
    self.table_name = 'events_enriched'
  end
end

# == Schema Information
#
# Table name: events_enriched
#
#  aggregation_type         :string
#  code                     :string           not null
#  filters                  :map              not null
#  grouped_by               :map              not null
#  properties               :map              not null
#  timestamp                :datetime         not null
#  value                    :string
#  charge_id                :string           not null
#  external_subscription_id :string           not null
#  organization_id          :string           not null
#  transaction_id           :string           not null
#
