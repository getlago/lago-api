# frozen_string_literal: true

class AddCurrencyToCustomers < ActiveRecord::Migration[7.0]
  def change
    add_column :customers, :currency, :string
  end
end
