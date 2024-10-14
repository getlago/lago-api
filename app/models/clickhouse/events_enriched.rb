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
#  code                     :string           not null, primary key
#  filters                  :string           not null
#  grouped_by               :string           not null
#  properties               :string           not null
#  timestamp                :datetime         not null
#  value                    :string
#  charge_id                :string           not null, primary key
#  external_subscription_id :string           not null, primary key
#  organization_id          :string           not null, primary key
#  transaction_id           :string           not null, primary key
#
