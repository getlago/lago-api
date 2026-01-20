# frozen_string_literal: true

class AddDunningCampaignEndedAt < ActiveRecord::Migration[8.0]
  def change
    add_column :customers, :dunning_campaign_ended_at, :datetime
  end
end
