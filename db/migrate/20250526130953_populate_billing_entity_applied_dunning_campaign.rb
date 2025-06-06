# frozen_string_literal: true

class PopulateBillingEntityAppliedDunningCampaign < ActiveRecord::Migration[8.0]
  def up
    # rubocop:disable Rails/SkipsModelValidations
    DunningCampaign.where(applied_to_organization: true).find_each do |dunning_campaign|
      BillingEntity.where(id: dunning_campaign.organization_id).update_all(applied_dunning_campaign_id: dunning_campaign.id)
    end
    # rubocop:enable Rails/SkipsModelValidations
  end

  def down
  end
end
