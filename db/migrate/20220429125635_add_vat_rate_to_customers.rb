# frozen_string_literal: true

class AddVatRateToCustomers < ActiveRecord::Migration[7.0]
  def up
    add_column :customers, :vat_rate, :float, null: true
  end

  def down
    remove_column :customers, :vat_rate
  end
end
