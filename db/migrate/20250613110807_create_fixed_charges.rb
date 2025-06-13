class CreateFixedCharges < ActiveRecord::Migration[8.0]
  def change
    create_enum :fixed_charges_charge_model, %w[standard gradutated]
    create_enum :fixed_charges_interval, %w[weekly monthly yearly quarterly]
    create_enum :fixed_charges_billing_period_duration_unit, %w[day  month]

    create_table :fixed_charges, id: :uuid do |t|
      t.belongs_to :organization, null: false, foreign_key: true, type: :uuid
      t.belongs_to :billing_entity, null: false, foreign_key: true, type: :uuid
      t.belongs_to :plan, null: false, foreign_key: true, type: :uuid
      t.belongs_to :add_on, null: false, foreign_key: true, type: :uuid
      t.belongs_to :parent, type: :uuid, index: true
      t.enum :charge_model, enum_type: "fixed_charges_charge_model", null: false, default: "standard"
      t.enum :interval, enum_type: "fixed_charges_interval", null: false, default: "monthly"
      t.jsonb :properties, null: false, default: {}
      t.string :invoice_display_name
      t.boolean :pay_in_advance, default: false, null: false
      t.boolean :prorated, default: false, null: false
      t.boolean :recurring, default: true, null: false
      t.integer :billing_period_duration
      t.enum :billing_period_duration_unit, enum_type: "fixed_charges_billing_period_duration_unit", null: false, default: "month"
      t.integer :trial_period, null: false, default: 0
      t.integer :untis, null: false, default: 0
      t.datetime :deleted_at, index: true

      t.timestamps
    end
  end
end
