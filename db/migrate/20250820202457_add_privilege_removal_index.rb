# frozen_string_literal: true

class AddPrivilegeRemovalIndex < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_index :entitlement_subscription_feature_removals,
      [:subscription_id, :entitlement_privilege_id],
      unique: true, where: "deleted_at IS NULL",
      algorithm: :concurrently
  end
end
