# frozen_string_literal: true

class CreateBillingOperationSegments < ActiveRecord::Migration[8.1]
  def change
    create_table :billing_operation_segments, id: :uuid do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid
      t.references :billing_operation, null: false, foreign_key: true, type: :uuid, index: false
      t.references :rate_card_rate, null: false, foreign_key: true, type: :uuid
      t.references :rate_override, foreign_key: true, type: :uuid
      t.integer :position, null: false
      t.datetime :started_at, null: false
      t.datetime :ended_at, null: false
      t.timestamps
      t.decimal :proration_ratio, precision: 30, scale: 10, null: false

      t.index [:billing_operation_id, :position], unique: true
      t.check_constraint "ended_at > started_at", name: "billing_operation_segments_positive_coverage"
      t.check_constraint "proration_ratio >= 0 AND proration_ratio <= 1", name: "billing_operation_segments_proration_ratio_bounds"
    end
  end
end
