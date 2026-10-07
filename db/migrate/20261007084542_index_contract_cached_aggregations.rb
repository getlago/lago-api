# frozen_string_literal: true

class IndexContractCachedAggregations < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  INDEX_NAME = :idx_cached_aggregation_contract_lookup

  def up
    if index_exists?(:cached_aggregations, nil, name: INDEX_NAME, valid: false)
      remove_index :cached_aggregations, name: INDEX_NAME, algorithm: :concurrently
    end

    add_index :cached_aggregations,
      [:contract_rate_card_id, :product_filter_id, :timestamp],
      order: {timestamp: :desc},
      where: "contract_rate_card_id IS NOT NULL",
      name: INDEX_NAME, algorithm: :concurrently, if_not_exists: true
  end

  def down
    remove_index :cached_aggregations, name: INDEX_NAME, algorithm: :concurrently, if_exists: true
  end
end
