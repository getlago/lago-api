# frozen_string_literal: true

class AddLegacyBillingFieldsCheckToPlans < ActiveRecord::Migration[8.0]
  def change
    # interval, amount_cents and pay_in_advance are only optional for
    # product-catalog plans: legacy plans keep the guarantee the NOT NULL
    # constraints used to give the v1 billing code.
    add_check_constraint :plans,
      %(pricing_type <> 'legacy' OR ("interval" IS NOT NULL AND amount_cents IS NOT NULL AND pay_in_advance IS NOT NULL)),
      name: "check_plans_on_legacy_billing_fields",
      validate: false
  end
end
