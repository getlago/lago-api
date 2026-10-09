# frozen_string_literal: true

class AddGinIndexesForContractSearch < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_index :contracts, "organization_id, name gin_trgm_ops", using: :gin, algorithm: :concurrently, if_not_exists: true
    add_index :contracts, "organization_id, external_id gin_trgm_ops", using: :gin, algorithm: :concurrently, if_not_exists: true

    # Contract search reaches through to the plan by name/code, so the plan
    # branch needs its own trigram indexes just like the contract columns.
    add_index :catalog_plans, "organization_id, name gin_trgm_ops", using: :gin, where: "deleted_at IS NULL", algorithm: :concurrently, if_not_exists: true
    add_index :catalog_plans, "organization_id, code gin_trgm_ops", using: :gin, where: "deleted_at IS NULL", algorithm: :concurrently, if_not_exists: true
  end
end
