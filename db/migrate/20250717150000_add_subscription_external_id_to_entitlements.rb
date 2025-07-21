# frozen_string_literal: true

class AddSubscriptionExternalIdToEntitlements < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    remove_index :entitlement_entitlements, name: "idx_on_entitlement_feature_id_plan_id_c45949ea26", column: %w[entitlement_feature_id plan_id],
      unique: true,
      where: "(deleted_at IS NULL)",
      algorithm: :concurrently,
      if_exists: true

    change_column_null :entitlement_entitlements, :plan_id, true

    add_reference :entitlement_entitlements, :subscription, index: {algorithm: :concurrently}, type: :uuid

    add_index :entitlement_entitlements, %w[entitlement_feature_id plan_id],
      unique: true,
      where: "(deleted_at IS NULL AND subscription_id IS NULL)",
      name: "idx_unique_feature_per_plan",
      algorithm: :concurrently,
      if_not_exists: true

    add_index :entitlement_entitlements, %w[entitlement_feature_id subscription_id],
      unique: true,
      where: "(deleted_at IS NULL AND plan_id IS NULL)",
      name: "idx_unique_feature_per_subscription",
      algorithm: :concurrently,
      if_not_exists: true
  end
end
