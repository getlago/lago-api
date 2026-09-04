# frozen_string_literal: true

class ValidateCatalogPlanEcosystemForeignKeys < ActiveRecord::Migration[8.0]
  def up
    validate_foreign_key :coupon_targets, :catalog_plans
    validate_foreign_key :plans_taxes, :catalog_plans
    validate_foreign_key :entitlement_entitlements, :catalog_plans

    validate_check_constraint :entitlement_entitlements, name: "entitlement_check_exactly_one_parent"
  end

  def down
  end
end
