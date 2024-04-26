# frozen_string_literal: true

class UpdateCachedAggregations < ActiveRecord::Migration[7.0]
  def change
    change_column_null :cached_aggregations, :event_id, true
    add_column :cached_aggregations, :current_amount, :decimal
  end
end
