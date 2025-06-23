# frozen_string_literal: true

class AddGroupedByToCachedAggregations < ActiveRecord::Migration[7.0]
  def change
    add_column :cached_aggregations, :grouped_by, :string, array: true, null: false, default: []
  end
end
