# frozen_string_literal: true

class ValidateRatesForeignKeysOnBillingCycles < ActiveRecord::Migration[8.0]
  def change
    validate_foreign_key :billing_cycles, :rate_card_rates
    validate_foreign_key :billing_cycles, :rate_overrides
  end
end
