# frozen_string_literal: true

# Unique, so a production organization has at most one sandbox even under concurrent links.
class AddOrganizationsProductionOrganizationIdIndex < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    # A failed concurrent build leaves an invalid index behind, which `if_not_exists` would then keep: drop it so that
    # a retry builds the index again.
    if index_exists?(:organizations, nil, name: :index_organizations_on_production_organization_id, valid: false)
      remove_index :organizations, name: :index_organizations_on_production_organization_id, algorithm: :concurrently
    end

    add_index :organizations, :production_organization_id,
      unique: true,
      name: :index_organizations_on_production_organization_id,
      algorithm: :concurrently,
      if_not_exists: true
  end

  def down
    remove_index :organizations, name: :index_organizations_on_production_organization_id, algorithm: :concurrently,
      if_exists: true
  end
end
