# frozen_string_literal: true

module BillingEntities
  class UpdateAppliedDunningCampaignService < BaseService
    Result = BaseResult[:billing_entity]
    def initialize(billing_entity:, dunning_campaign: nil)
      @billing_entity = billing_entity
      @dunning_campaign = dunning_campaign
      super
    end

    def call
      return result.not_found_failure!(resource: "billing_entity") if billing_entity.nil?
      return unless billing_entity.applied_dunning_campaign != dunning_campaign

      billing_entity.reset_customers_last_dunning_campaign_attempt
      billing_entity.update!(applied_dunning_campaign: dunning_campaign)
    end

    private

    attr_reader :billing_entity, :dunning_campaign
  end
end
