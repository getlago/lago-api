# frozen_string_literal: true

class CreateUsageAttributionValues < ActiveRecord::Migration[8.0]
  def change
    create_table :usage_attribution_values, id: :uuid do |t|
      t.references :organization, type: :uuid, null: false, foreign_key: true, index: true
      t.references :usage_attribution_type, type: :uuid, null: false, foreign_key: true, index: true
      t.references :customer, type: :uuid, null: false, foreign_key: true, index: true
      t.references :parent, type: :uuid, null: true, foreign_key: {to_table: :usage_attribution_values}, index: true

      t.string :value, null: false
      t.datetime :last_seen_at

      t.datetime :deleted_at

      t.timestamps

      t.index %i[customer_id usage_attribution_type_id value],
        unique: true,
        name: "index_usage_attribution_values_on_customer_type_and_value"
      t.index %i[customer_id last_seen_at]
    end
  end
end
