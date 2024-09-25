# frozen_string_literal: true

class AddTaxesDeductionRateFieldsToFeesAndAppliedTaxes < ActiveRecord::Migration[7.1]
  def change
    safety_assured do
      change_table :fees do |t|
        t.float :taxes_base_rate, default: 1.0, null: false
      end

      change_table :invoices_taxes do |t|
        t.bigint :taxable_base_amount_cents, default: 0, null: false
      end
    end
  end
end
