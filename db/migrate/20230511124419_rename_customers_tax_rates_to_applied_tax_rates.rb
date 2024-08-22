# frozen_string_literal: true

class RenameCustomersTaxRatesToAppliedTaxRates < ActiveRecord::Migration[7.0]
  def change
    safety_assured do
      rename_table :customers_tax_rates, :applied_tax_rates
    end
  end
end
