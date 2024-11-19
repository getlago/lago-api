# frozen_string_literal: true

class ResetCustomersCountCounterCacheForDunningCampaigns < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    DunningCampaign.find_each(batch_size: 1000) do |campaign|
      campaign.update_column(:customers_count, campaign.customers.kept.count)
    end
  end

  def down
    # there is no reason to block rollback with an irreversible migration
  end
end
