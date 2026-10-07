# frozen_string_literal: true

class ValidateContractCachedAggregationForeignKeys < ActiveRecord::Migration[8.0]
  def change
    validate_foreign_key :cached_aggregations, :contract_rate_cards
    validate_foreign_key :cached_aggregations, :product_filters
  end
end
