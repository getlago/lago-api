# frozen_string_literal: true

class AddTaxIdentificationNumber < ActiveRecord::Migration[7.0]
  def change
    add_column :customers, :tax_identification_number, :string, null: true
    add_column :organizations, :tax_identification_number, :string, null: true
  end
end
