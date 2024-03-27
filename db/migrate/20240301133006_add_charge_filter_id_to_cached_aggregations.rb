# frozen_string_literal: true

class AddChargeFilterIdToCachedAggregations < ActiveRecord::Migration[7.0]
  def change
    add_column :cached_aggregations, :charge_filter_id, :uuid, null: true
    add_index :cached_aggregations,
      %i[organization_id timestamp charge_id charge_filter_id],
      name: :index_timestamp_filter_lookup
  end
end
