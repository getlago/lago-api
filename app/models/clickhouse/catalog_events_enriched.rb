# frozen_string_literal: true

module Clickhouse
  class CatalogEventsEnriched < BaseRecord
    self.table_name = "catalog_events_enriched"
    self.primary_key = [:organization_id, :code, :external_contract_id, :timestamp]
  end
end

# == Schema Information
#
# Table name: catalog_events_enriched
# Database name: clickhouse
#
#  attribution_labels         :string           not null
#  code                       :string           not null, primary key
#  decimal_value              :decimal(38, 26)
#  enriched_at                :datetime         not null
#  precise_total_amount_cents :decimal(40, 15)
#  properties                 :string           not null
#  sorted_properties          :string           not null
#  timestamp                  :datetime         not null, primary key
#  value                      :string
#  contract_id                :string
#  external_contract_id       :string           not null, primary key
#  organization_id            :string           not null, primary key
#  transaction_id             :string           not null
#
