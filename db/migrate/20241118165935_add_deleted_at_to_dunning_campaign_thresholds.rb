# frozen_string_literal: true

class AddDeletedAtToDunningCampaignThresholds < ActiveRecord::Migration[7.1]
  def change
    add_column :dunning_campaign_thresholds, :deleted_at, :timestamp

    safety_assured do
      add_index :dunning_campaign_thresholds, :deleted_at
    end
  end
end
