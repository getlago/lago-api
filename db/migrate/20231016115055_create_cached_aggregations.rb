# frozen_string_literal: true

class CreateCachedAggregations < ActiveRecord::Migration[7.0]
  def change
    create_table :cached_aggregations, id: :uuid do |t|
      t.references :organization, type: :uuid, null: false, index: true

      t.uuid :event_id, null: false, index: true
      t.datetime :timestamp, null: false
      t.string :external_subscription_id, null: false, index: true
      t.references :charge, type: :uuid, null: false, index: true
      t.references :group, type: :uuid, foreign_key: true, null: true, index: true

      t.decimal :current_aggregation
      t.decimal :max_aggregation
      t.decimal :max_aggregation_with_proration

      t.timestamps

      t.index %i[organization_id timestamp charge_id], name: 'index_timestamp_lookup'
      t.index %i[organization_id timestamp charge_id group_id], name: 'index_timestamp_group_lookup'
    end
  end
end
