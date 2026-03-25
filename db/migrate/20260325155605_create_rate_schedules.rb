# frozen_string_literal: true

class CreateRateSchedules < ActiveRecord::Migration[8.0]
  def change
    create_enum :rate_schedule_billing_interval_unit, %w[day week month year]
    create_enum :rate_schedule_charge_model, %w[standard graduated package percentage volume graduated_percentage custom dynamic]
    create_enum :rate_schedule_regroup_paid_fees, %w[invoice]

    create_table :rate_schedules, id: :uuid do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid
      t.references :plan_product_item, null: false, foreign_key: true, type: :uuid
      t.references :product_item, null: false, foreign_key: true, type: :uuid
      t.references :product_item_filter, foreign_key: true, type: :uuid

      t.integer :billing_interval_count, null: false
      t.enum :billing_interval_unit, enum_type: :rate_schedule_billing_interval_unit, null: false
      t.integer :billing_cycle_count

      t.enum :charge_model, enum_type: :rate_schedule_charge_model, null: false
      t.jsonb :properties, null: false, default: {}

      t.boolean :pay_in_advance, null: false, default: false
      t.boolean :prorated, null: false, default: false
      t.boolean :invoiceable, null: false, default: true
      t.bigint :min_amount_cents, null: false, default: 0
      t.string :amount_currency, null: false

      t.decimal :units, precision: 30, scale: 10
      t.string :invoice_display_name
      t.integer :position, null: false
      t.enum :regroup_paid_fees, enum_type: :rate_schedule_regroup_paid_fees
      t.jsonb :applied_pricing_unit

      t.datetime :deleted_at
      t.timestamps
    end

    add_index :rate_schedules, :deleted_at
    add_index :rate_schedules, [:plan_product_item_id, :position],
      unique: true,
      where: "deleted_at IS NULL",
      name: :idx_rate_schedules_on_plan_product_item_and_position
  end
end
