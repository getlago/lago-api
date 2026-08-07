# frozen_string_literal: true

class CreateUsageRealtimeProjections < ActiveRecord::Migration[8.0]
  def change
    create_table :usage_realtime_projections,
      primary_key: %i[subscription_id billing_period_id charge_id charge_filter_id grouped_by] do |t|
      t.uuid :subscription_id, null: false
      t.uuid :billing_period_id, null: false
      t.uuid :charge_id, null: false
      # Sentinel "" = the charge's default bucket (no matching filter)
      t.string :charge_filter_id, null: false, default: ""
      t.string :grouped_by, null: false, default: "{}"

      t.uuid :organization_id, null: false
      t.uuid :plan_id
      t.string :code, null: false
      t.string :aggregation_type, null: false
      t.datetime :period_charges_from, null: false
      t.datetime :period_charges_to, null: false
      t.bigint :events_count, null: false, default: 0
      t.decimal :units, null: false, default: "0.0"
      t.datetime :last_event_at
      t.datetime :last_ingested_at

      t.index %i[organization_id subscription_id],
        name: "idx_usage_realtime_projections_on_org_and_subscription"
    end
  end
end
