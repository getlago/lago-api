# frozen_string_literal: true

class CreateRateOverrides < ActiveRecord::Migration[8.0]
  def change
    create_table :rate_overrides, id: :uuid do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid

      t.enum :rate_model, enum_type: :rate_card_rate_model, null: false
      t.jsonb :rate_properties, null: false, default: {}
      t.bigint :min_amount_cents, null: false, default: 0

      # null billing interval fields inherit the card's active rate.
      t.integer :billing_interval_count
      t.enum :billing_interval_unit, enum_type: :rate_card_rate_billing_interval_unit

      t.decimal :pricing_unit_conversion_rate, precision: 30, scale: 10

      t.datetime :deleted_at

      t.timestamps

      t.index :deleted_at
    end

    safety_assured do
      add_foreign_key :rate_phases, :rate_overrides, column: :rate_override_id
      add_index :rate_phases, :rate_override_id
    end
  end
end
