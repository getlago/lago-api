# frozen_string_literal: true

class AddRateChangeToBillingOperationCancellationReason < ActiveRecord::Migration[8.1]
  def change
    add_enum_value :billing_operation_cancellation_reason, "rate_change", if_not_exists: true
  end
end
