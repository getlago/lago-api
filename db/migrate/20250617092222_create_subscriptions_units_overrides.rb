class CreateSubscriptionsUnitsOverrides < ActiveRecord::Migration[8.0]
  def change
    create_table :subscriptions_units_overrides, id: :uuid do |t|
      t.decimal :units, precision: 30, scale: 10, null: false
      t.references :subscription, type: :uuid, null: false, foreign_key: true
      t.references :fixed_charge, type: :uuid, null: true, foreign_key: true
      t.references :charge, type: :uuid, null: true, foreign_key: true

      t.index [:subscription_id, :fixed_charge_id, :charge_id], unique: true

      t.timestamps
    end
  end
end
