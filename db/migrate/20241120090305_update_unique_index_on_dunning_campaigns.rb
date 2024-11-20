# frozen_string_literal: true

class UpdateUniqueIndexOnDunningCampaigns < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    remove_index :dunning_campaigns, %i[organization_id code], unique: true, algorithm: :concurrently

    add_index :dunning_campaigns,
      [:organization_id, :code],
      unique: true,
      where: "deleted_at IS NULL",
      algorithm: :concurrently
  end
end
