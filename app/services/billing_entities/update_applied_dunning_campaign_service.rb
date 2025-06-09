# frozen_string_literal: true

module BillingEntities
  class UpdateAppliedDunningCampaignService < BaseService
    Result = BaseResult[:billing_entity]
    def initialize(billing_entity:, applied_dunning_campaign_id: nil)
      @billing_entity = billing_entity
      @applied_dunning_campaign_id = applied_dunning_campaign_id
      super
    end

    def call
      return result.not_found_failure!(resource: "billing_entity") if billing_entity.nil?
      return if billing_entity.applied_dunning_campaign_id == applied_dunning_campaign_id

      dunning_campaign = DunningCampaign.find(applied_dunning_campaign_id) if applied_dunning_campaign_id
      billing_entity.reset_customers_last_dunning_campaign_attempt
      billing_entity.update!(applied_dunning_campaign: dunning_campaign)
      result.billing_entity = billing_entity
      result
    rescue ActiveRecord::RecordNotFound
      result.not_found_failure!(resource: "dunning_campaign")
    end

    private

    attr_reader :billing_entity, :applied_dunning_campaign_id
  end
end
