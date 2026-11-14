# frozen_string_literal: true

class AddContractToEntitlements < ActiveRecord::Migration[8.0]
  def up
    add_column :entitlement_entitlements, :contract_id, :uuid, null: true, if_not_exists: true
    add_column :entitlement_subscription_feature_removals, :contract_id, :uuid, null: true, if_not_exists: true
    add_foreign_key :entitlement_entitlements, :contracts, validate: false, if_not_exists: true
    add_foreign_key :entitlement_subscription_feature_removals, :contracts, validate: false, if_not_exists: true

    # A removal now belongs to a subscription or a contract.
    change_column_null :entitlement_subscription_feature_removals, :subscription_id, true

    # Existing rows have no contract_id and one non-null parent (the old check) or a
    # non-null subscription_id (the old NOT NULL), so both checks validate in the next
    # migration. Swapping the entitlement check in one transaction leaves no gap.
    remove_check_constraint :entitlement_entitlements, name: "entitlement_check_exactly_one_parent"
    add_check_constraint :entitlement_entitlements,
      "num_nonnulls(plan_id, catalog_plan_id, subscription_id, contract_id) = 1",
      name: "entitlement_check_exactly_one_parent",
      validate: false,
      if_not_exists: true
    add_check_constraint :entitlement_subscription_feature_removals,
      "num_nonnulls(subscription_id, contract_id) = 1",
      name: "entitlement_removal_check_exactly_one_owner",
      validate: false,
      if_not_exists: true
  end

  def down
    remove_check_constraint :entitlement_subscription_feature_removals,
      name: "entitlement_removal_check_exactly_one_owner",
      if_exists: true
    remove_check_constraint :entitlement_entitlements, name: "entitlement_check_exactly_one_parent"
    add_check_constraint :entitlement_entitlements,
      "num_nonnulls(plan_id, catalog_plan_id, subscription_id) = 1",
      name: "entitlement_check_exactly_one_parent",
      if_not_exists: true

    change_column_null :entitlement_subscription_feature_removals, :subscription_id, false

    remove_foreign_key :entitlement_subscription_feature_removals, :contracts, if_exists: true
    remove_foreign_key :entitlement_entitlements, :contracts, if_exists: true
    # Reverts the column this migration added.
    remove_column :entitlement_subscription_feature_removals, :contract_id, if_exists: true # rubocop:disable Lago/NoDropColumnOrTable
    remove_column :entitlement_entitlements, :contract_id, if_exists: true # rubocop:disable Lago/NoDropColumnOrTable
  end
end
