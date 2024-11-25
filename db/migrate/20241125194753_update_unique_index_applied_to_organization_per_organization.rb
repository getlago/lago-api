# frozen_string_literal: true

class UpdateUniqueIndexAppliedToOrganizationPerOrganization < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    remove_index :dunning_campaigns,
      %i[organization_id],
      unique: true,
      algorithm: :concurrently,
      where: "applied_to_organization = true",
      name: "index_unique_applied_to_organization_per_organization"

    add_index :dunning_campaigns,
      %i[organization_id],
      unique: true,
      algorithm: :concurrently,
      where: "applied_to_organization = true AND deleted_at IS NULL",
      name: "index_unique_applied_to_organization_per_organization"
  end
end
