# frozen_string_literal: true

class AddDunningCampaignToCustomers < ActiveRecord::Migration[7.1]
  def change
    safety_assured do
      change_table :customers, bulk: true do |t|
        t.references :applied_dunning_campaign, type: :uuid, null: true, foreign_key: {to_table: :dunning_campaigns}, index: true
        t.boolean :exclude_from_dunning_campaign, default: false, null: false
        t.integer :last_dunning_campaign_attempt, default: 0, null: false
        t.timestamp :last_dunning_campaign_attempt_at
      end
    end
  end
end
