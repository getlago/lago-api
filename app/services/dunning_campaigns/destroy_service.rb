# frozen_string_literal: true

module DunningCampaigns
  class DestroyService < BaseService
    def initialize(dunning_campaign:)
      @dunning_campaign = dunning_campaign

      super
    end

    def call
      return result.not_found_failure!(resource: "dunning_campaign") unless dunning_campaign
      return result.forbidden_failure! unless dunning_campaign.organization.auto_dunning_enabled?

      ActiveRecord::Base.transaction do
        dunning_campaign.reset_customers_last_attempt
        dunning_campaign.discard!
        dunning_campaign.thresholds.discard_all
      end

      result.dunning_campaign = dunning_campaign
      result
    end

    private

    attr_reader :dunning_campaign
  end
end
