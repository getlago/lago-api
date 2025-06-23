# frozen_string_literal: true

class UpdateUniqueIndexOnDunningCampaignThresholds < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    remove_index :dunning_campaign_thresholds, %i[dunning_campaign_id currency], unique: true, algorithm: :concurrently

    add_index :dunning_campaign_thresholds,
      [:dunning_campaign_id, :currency],
      unique: true,
      where: "deleted_at IS NULL",
      algorithm: :concurrently
  end
end
