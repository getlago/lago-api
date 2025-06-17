# frozen_string_literal: true

class AddDeletedAtToDunningCampaigns < ActiveRecord::Migration[7.1]
  def change
    add_column :dunning_campaigns, :deleted_at, :timestamp

    safety_assured do
      add_index :dunning_campaigns, :deleted_at
    end
  end
end
