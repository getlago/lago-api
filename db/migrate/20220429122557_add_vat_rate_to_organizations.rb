# frozen_string_literal: true

class AddVatRateToOrganizations < ActiveRecord::Migration[7.0]
  def up
    add_column :organizations, :vat_rate, :float, null: true
  end

  def down
    remove_column :organizations, :vat_rate
  end
end
