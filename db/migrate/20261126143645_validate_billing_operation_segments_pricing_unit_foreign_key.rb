# frozen_string_literal: true

class ValidateBillingOperationSegmentsPricingUnitForeignKey < ActiveRecord::Migration[8.1]
  def change
    validate_foreign_key :billing_operation_segments, :pricing_units
  end
end
