# frozen_string_literal: true

class AddDunningCampaignCompletedToCustomers < ActiveRecord::Migration[7.1]
  def change
    add_column :customers, :dunning_campaign_completed, :boolean, default: false
  end
end
