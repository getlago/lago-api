# frozen_string_literal: true

class AddDefaultCurrencyToOrganizations < ActiveRecord::Migration[7.0]
  def change
    add_column :organizations, :default_currency, :string, null: false, default: "USD"
  end
end
