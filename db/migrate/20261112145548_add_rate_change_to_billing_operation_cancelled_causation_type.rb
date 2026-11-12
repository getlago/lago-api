# frozen_string_literal: true

class AddRateChangeToBillingOperationCancelledCausationType < ActiveRecord::Migration[8.1]
  def change
    add_enum_value :billing_operation_cancelled_causation_type, "rate_change", if_not_exists: true
  end
end
