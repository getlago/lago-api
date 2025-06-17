# frozen_string_literal: true

class AddAppliedToOrganizationUniqueIndexToDunningCampaigns < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_index :dunning_campaigns, [:organization_id],
      unique: true,
      algorithm: :concurrently,
      where: "applied_to_organization = true",
      name: "index_unique_applied_to_organization_per_organization"
  end
end
