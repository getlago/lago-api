# frozen_string_literal: true

class AddPricingUnitToBillingCycles < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_reference :billing_cycles, :pricing_unit, type: :uuid, index: {algorithm: :concurrently}
    add_foreign_key :billing_cycles, :pricing_units, validate: false
  end
end
