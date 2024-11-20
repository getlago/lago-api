# frozen_string_literal: true

class AddCustomersCountToDunningCampaigns < ActiveRecord::Migration[7.1]
  def change
    add_column :dunning_campaigns, :customers_count, :integer, default: 0, null: false
  end
end
