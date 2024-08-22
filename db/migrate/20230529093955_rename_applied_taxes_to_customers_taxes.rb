# frozen_string_literal: true

class RenameAppliedTaxesToCustomersTaxes < ActiveRecord::Migration[7.0]
  def change
    safety_assured do
      rename_table :applied_taxes, :customers_taxes
    end
  end
end
