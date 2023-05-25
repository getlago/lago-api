# frozen_string_literal: true

class CreateCustomersTaxRates < ActiveRecord::Migration[7.0]
  def change
    add_column :tax_rates, :applied_by_default, :boolean, null: false, default: false

    create_table :customers_tax_rates, id: :uuid do |t|
      t.references :customer, type: :uuid, foreign_key: true, null: false, index: true
      t.references :tax_rate, type: :uuid, foreign_key: true, null: false, index: true

      t.timestamps
    end
  end
end
