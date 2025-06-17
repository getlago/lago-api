# frozen_string_literal: true

class AddTaxesDeductionRateFieldsToFeesAndAppliedTaxes < ActiveRecord::Migration[7.1]
  def change
    add_column :fees, :taxes_base_rate, :float, default: 1.0, null: false
    add_column :invoices_taxes, :taxable_base_amount_cents, :bigint, default: 0, null: false
  end
end
