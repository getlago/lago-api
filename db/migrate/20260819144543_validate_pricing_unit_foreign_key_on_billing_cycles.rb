# frozen_string_literal: true

class ValidatePricingUnitForeignKeyOnBillingCycles < ActiveRecord::Migration[8.0]
  def change
    validate_foreign_key :billing_cycles, :pricing_units
  end
end
