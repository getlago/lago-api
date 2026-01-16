# frozen_string_literal: true

class CreateEnrichedEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :enriched_events, id: false, primary_key: %i[id timestamp], options: "PARTITION BY RANGE (timestamp)" do |t|
      t.uuid :id, null: false, default: -> { "gen_random_uuid()" }
      t.uuid :organization_id, null: false
      t.references :event, null: false, foreign_key: true, type: :uuid
      t.string :transaction_id, null: false
      t.string :external_subscription_id, null: false
      t.string :code, null: false
      t.datetime :timestamp, null: false
      t.uuid :subscription_id, null: false
      t.uuid :plan_id, null: false
      t.uuid :charge_id, null: false
      t.uuid :charge_filter_id
      t.jsonb :properties, null: false, default: {}
      t.jsonb :grouped_by, null: false, default: {}
      t.string :value, null: true
      t.decimal :decimal_value, precision: 40, scale: 15, null: false, default: 0.0
      t.datetime :enriched_at, null: false

      t.index %i[organization_id subscription_id charge_id charge_filter_id timestamp], name: "idx_billing_on_enriched_events"
      t.index %i[organization_id external_subscription_id code timestamp], name: "idx_lookup_on_enriched_events"
      t.index %i[organization_id external_subscription_id transaction_id timestamp charge_id], unique: true, name: "idx_unique_on_enriched_events"
    end
  end
end
