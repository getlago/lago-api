# frozen_string_literal: true

class ValidateLegacyBillingFieldsCheckOnPlans < ActiveRecord::Migration[8.0]
  def change
    validate_check_constraint :plans, name: "check_plans_on_legacy_billing_fields"
  end
end
