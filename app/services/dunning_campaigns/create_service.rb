# frozen_string_literal: true

module DunningCampaigns
  class CreateService < BaseService
    def initialize(organization:, params:)
      @organization = organization
      @params = params

      super
    end

    def call
      dunning_campaign = organization.dunning_campaigns.new(
        applied_to_organization: params[:applied_to_organization],
        code: params[:code],
        days_between_attempts: params[:days_between_attempts],
        max_attempts: params[:max_attempts],
        name: params[:name],
        description: params[:description]
      )

      dunning_campaign.save!

      result.dunning_campaign = dunning_campaign
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :organization, :params
  end
end
