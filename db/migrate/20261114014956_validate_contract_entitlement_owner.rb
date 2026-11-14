# frozen_string_literal: true

class ValidateContractEntitlementOwner < ActiveRecord::Migration[8.0]
  def up
    validate_foreign_key :entitlement_entitlements, :contracts
    validate_foreign_key :entitlement_subscription_feature_removals, :contracts

    validate_check_constraint :entitlement_entitlements, name: "entitlement_check_exactly_one_parent"
    validate_check_constraint :entitlement_subscription_feature_removals,
      name: "entitlement_removal_check_exactly_one_owner"
  end

  def down
  end
end
