# frozen_string_literal: true

class RemoveDunningCampaignCompletedFromCustomers < ActiveRecord::Migration[7.1]
  def change
    safety_assured do
      remove_column :customers, :dunning_campaign_completed, :boolean, default: false
    end
  end
end
