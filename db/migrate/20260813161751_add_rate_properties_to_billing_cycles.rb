# frozen_string_literal: true

class AddRatePropertiesToBillingCycles < ActiveRecord::Migration[8.0]
  def change
    add_column :billing_cycles, :rate_properties, :jsonb, null: false, default: {}
  end
end
