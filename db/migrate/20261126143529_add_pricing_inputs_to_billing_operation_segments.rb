# frozen_string_literal: true

class AddPricingInputsToBillingOperationSegments < ActiveRecord::Migration[8.1]
  def change
    add_column :billing_operation_segments, :units, :decimal, if_not_exists: true
    add_column :billing_operation_segments, :prepaid_units, :decimal, if_not_exists: true
    add_column :billing_operation_segments, :units_intervals, :jsonb, if_not_exists: true
    add_column :billing_operation_segments, :rate_properties, :jsonb, if_not_exists: true
    add_column :billing_operation_segments, :currency, :string, if_not_exists: true
    add_column :billing_operation_segments, :pricing_unit_id, :uuid, if_not_exists: true
    add_foreign_key :billing_operation_segments, :pricing_units, validate: false, if_not_exists: true
  end
end
