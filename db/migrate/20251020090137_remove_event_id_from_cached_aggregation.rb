# frozen_string_literal: true

class RemoveEventIdFromCachedAggregation < ActiveRecord::Migration[8.0]
  def up
    safety_assured do
      remove_column :cached_aggregations, :event_id
    end
  end
end
