# frozen_string_literal: true

class AddRatesForeignKeysToBillingCycles < ActiveRecord::Migration[8.0]
  def change
    add_foreign_key :billing_cycles, :rate_card_rates, validate: false
    add_foreign_key :billing_cycles, :rate_overrides, validate: false
  end
end
