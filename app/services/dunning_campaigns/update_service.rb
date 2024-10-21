# frozen_string_literal: true

module DunningCampaigns
  class UpdateService < BaseService
    def initialize(organization:, dunning_campaign:, params:)
      @dunning_campaign = dunning_campaign
      @organization = organization
      @params = params

      super
    end

    def call
      return result.forbidden_failure! unless organization.auto_dunning_enabled?
      return result.not_found_failure!(resource: "dunning_campaign") unless dunning_campaign

      ActiveRecord::Base.transaction do
        unless params[:applied_to_organization].nil?
          organization
            .dunning_campaigns
            .applied_to_organization
            .update_all(applied_to_organization: false) # rubocop:disable Rails/SkipsModelValidations

          dunning_campaign.applied_to_organization = params[:applied_to_organization]
        end

        dunning_campaign.save!
      end

      result.dunning_campaign = dunning_campaign
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :dunning_campaign, :organization, :params
  end
end
