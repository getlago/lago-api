# frozen_string_literal: true

class ValidateContractCachedAggregationForeignKeys < ActiveRecord::Migration[8.0]
  def change
    validate_foreign_key :cached_aggregations, :contracts
    validate_foreign_key :cached_aggregations, :products
    validate_foreign_key :cached_aggregations, :product_filters
  end
end
