# frozen_string_literal: true

class AddContractIdentityToCachedAggregations < ActiveRecord::Migration[8.0]
  def change
    add_column :cached_aggregations, :contract_rate_card_id, :uuid, if_not_exists: true
    add_column :cached_aggregations, :product_filter_id, :uuid, if_not_exists: true
    change_column_null :cached_aggregations, :charge_id, true
    add_foreign_key :cached_aggregations, :contract_rate_cards, validate: false, if_not_exists: true
    add_foreign_key :cached_aggregations, :product_filters, validate: false, if_not_exists: true
  end
end
