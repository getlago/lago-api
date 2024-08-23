# frozen_string_literal: true

class CreateAppliedUsageThresholds < ActiveRecord::Migration[7.1]
  def change
    create_table :applied_usage_thresholds, id: :uuid do |t|
      t.references :usage_threshold, null: false, foreign_key: true, type: :uuid
      t.references :invoice, null: false, foreign_key: true, type: :uuid

      t.timestamps

      t.index %i[usage_threshold_id invoice_id], unique: true
    end
  end
end
