# frozen_string_literal: true

class AddGinIndexesForSubscriptionSearchFields < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_index :subscriptions, "organization_id, name gin_trgm_ops", using: :gin, algorithm: :concurrently, if_not_exists: true
    add_index :subscriptions, "organization_id, external_id gin_trgm_ops", using: :gin, algorithm: :concurrently, if_not_exists: true
    add_index :plans, "organization_id, name gin_trgm_ops", using: :gin, where: "deleted_at IS NULL", algorithm: :concurrently, if_not_exists: true
    add_index :plans, "organization_id, code gin_trgm_ops", using: :gin, where: "deleted_at IS NULL", algorithm: :concurrently, if_not_exists: true
  end
end
