# frozen_string_literal: true

class CreateRateCardRates < ActiveRecord::Migration[8.0]
  def change
    create_enum :rate_card_rate_model, %w[standard graduated package percentage volume graduated_percentage custom dynamic]
    create_enum :rate_card_rate_billing_interval_unit, %w[day week month year]

    create_table :rate_card_rates, id: :uuid do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid
      t.references :rate_card, null: false, foreign_key: true, type: :uuid

      t.datetime :effective_datetime, null: false

      t.enum :rate_model, enum_type: :rate_card_rate_model, null: false
      t.jsonb :rate_properties, null: false, default: {}

      t.bigint :min_amount_cents, null: false, default: 0
      t.integer :billing_interval_count, null: false, default: 1
      t.enum :billing_interval_unit, enum_type: :rate_card_rate_billing_interval_unit, null: false

      t.decimal :applied_pricing_unit_conversion_rate, precision: 30, scale: 10

      t.datetime :deleted_at

      t.timestamps

      t.index :deleted_at
      t.index [:rate_card_id, :effective_datetime],
        unique: true,
        where: "deleted_at IS NULL",
        name: "index_rate_card_rates_on_rate_card_id_and_effective_datetime"

      t.check_constraint "billing_interval_count >= 1",
        name: "rate_card_rates_billing_interval_count_positive"
    end
  end
end
