# frozen_string_literal: true

class AddPropertiesToPlans < ActiveRecord::Migration[7.0]
  def change
    change_table :plans do |t|
      t.string :code, null: false
      t.integer :frequency, null: false
      t.string :description
      t.integer :billing_period, null: false
      t.boolean :pro_rata, null: false
      t.integer :amount_cents, null: false
      t.string :currency, null: false
      t.float :vat_rate
      t.float :trial_period

      t.index %w[code organization_id], unique: true
    end
  end
end
