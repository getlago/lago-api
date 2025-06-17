# frozen_string_literal: true

class IndexCachedAggregation < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_index :cached_aggregations,
      %i[timestamp charge_id external_subscription_id],
      algorithm: :concurrently,
      name: :idx_on_timestamp_charge_id_external_subscription_id
  end
end
