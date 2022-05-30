class CreateAppliedAddOns < ActiveRecord::Migration[7.0]
  def change
    create_table :applied_add_ons, id: :uuid do |t|
      t.references :add_on, type: :uuid, null: false
      t.references :customer, type: :uuid, null: false

      t.integer :amount_cents, null: false
      t.string :amount_currency, null: false

      t.index %i[add_on_id customer_id], unique: true

      t.timestamps
    end
  end
end
