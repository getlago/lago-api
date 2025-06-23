# frozen_string_literal: true

class SetDunningCampaignCompletedToCustomers < ActiveRecord::Migration[7.1]
  def change
    reversible do |dir|
      dir.up do
        safety_assured do
          # Set dunning_campaign_completed when the explicit assigned campaign is completed.
          execute <<-SQL
            UPDATE customers c
            SET dunning_campaign_completed = true
            FROM dunning_campaigns dc
            WHERE c.applied_dunning_campaign_id = dc.id
            AND c.dunning_campaign_completed = false
            AND c.last_dunning_campaign_attempt >= dc.max_attempts;
          SQL

          # Set dunning_campaign_completed when the campaign inherited from organization is completed.
          execute <<-SQL
            UPDATE customers c
            SET dunning_campaign_completed = true
            FROM dunning_campaigns dc
            WHERE c.organization_id = dc.organization_id
            AND dc.applied_to_organization = true
            AND c.applied_dunning_campaign_id IS NULL
            AND c.dunning_campaign_completed = false
            AND c.exclude_from_dunning_campaign = false
            AND c.last_dunning_campaign_attempt >= dc.max_attempts;
          SQL
        end
      end
    end
  end
end
