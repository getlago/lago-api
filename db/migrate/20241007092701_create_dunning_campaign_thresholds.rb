# frozen_string_literal: true

class CreateDunningCampaignThresholds < ActiveRecord::Migration[7.1]
  def change
    create_table :dunning_campaign_thresholds, id: :uuid do |t|
      t.references :dunning_campaign, null: false, foreign_key: true, type: :uuid

      t.string :currency, null: false
      t.bigint :amount_cents, null: false

      t.timestamps

      t.index %i[dunning_campaign_id currency], unique: true
    end
  end
end
