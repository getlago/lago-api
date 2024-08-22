# frozen_string_literal: true

class RenameTaxRatesToTaxes < ActiveRecord::Migration[7.0]
  def change
    safety_assured do
      rename_table :tax_rates, :taxes
      rename_table :applied_tax_rates, :applied_taxes

      rename_column :taxes, :applied_by_default, :applied_to_organization
      rename_column :taxes, :value, :rate
      rename_column :applied_taxes, :tax_rate_id, :tax_id
    end
  end
end
