# frozen_string_literal: true

class CreatePersistedMetrics < ActiveRecord::Migration[7.0]
  def change
    create_table :persisted_metrics, id: :uuid do |t|
      t.references :customer, type: :uuid, foreign_key: true, null: false

      t.string :external_subscription_id, null: false
      t.string :external_id, null: false, index: true
      t.datetime :added_at, null: false
      t.datetime :removed_at

      t.timestamps

      t.index [:customer_id, :external_subscription_id], name: :index_search_persisted_metrics
    end
  end
end
