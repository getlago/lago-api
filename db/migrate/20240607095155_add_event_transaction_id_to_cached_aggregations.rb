# frozen_string_literal: true

class AddEventTransactionIdToCachedAggregations < ActiveRecord::Migration[7.0]
  def change
    add_column :cached_aggregations, :event_transaction_id, :string
    safety_assured do
      add_index :cached_aggregations, %i[organization_id event_transaction_id], name: 'index_cached_aggregations_on_event_transaction_id'
    end
  end
end
