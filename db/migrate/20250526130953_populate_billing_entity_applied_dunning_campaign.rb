# frozen_string_literal: true

class PopulateBillingEntityAppliedDunningCampaign < ActiveRecord::Migration[8.0]
  class DunningCampaign < ActiveRecord::Base
    self.table_name = "dunning_campaigns"
    belongs_to :organization, class_name: "Organization"
  end

  def up
    DunningCampaign.where(applied_to_organization: true).find_each do |dunning_campaign|
      BillingEntity.where(id: dunning_campaign.organization_id).update_all(applied_dunning_campaign_id: dunning_campaign.id)
    end
  end

  def down
  end
end
