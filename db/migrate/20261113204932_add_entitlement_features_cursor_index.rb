# frozen_string_literal: true

class AddEntitlementFeaturesCursorIndex < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    if index_exists?(:entitlement_features, nil, name: :index_entitlement_features_by_cursor, valid: false)
      remove_index :entitlement_features, name: :index_entitlement_features_by_cursor, algorithm: :concurrently
    end

    add_index :entitlement_features,
      [:organization_id, :created_at, :id],
      order: {created_at: :desc, id: :desc},
      where: "deleted_at IS NULL",
      name: :index_entitlement_features_by_cursor,
      algorithm: :concurrently,
      if_not_exists: true
  end

  def down
    remove_index :entitlement_features, name: :index_entitlement_features_by_cursor, algorithm: :concurrently, if_exists: true
  end
end
