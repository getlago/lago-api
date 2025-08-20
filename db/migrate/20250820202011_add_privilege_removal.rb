# frozen_string_literal: true

class AddPrivilegeRemoval < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_reference :entitlement_subscription_feature_removals, :entitlement_privilege, index: {algorithm: :concurrently}, type: :uuid, null: true
  end
end
