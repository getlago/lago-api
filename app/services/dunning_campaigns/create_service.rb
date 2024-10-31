# frozen_string_literal: true

module DunningCampaigns
  class CreateService < BaseService
    def initialize(organization:, params:)
      @organization = organization
      @params = params

      super
    end

    def call
      return result.forbidden_failure! unless organization.auto_dunning_enabled?
      # TODO: At least one threshold currency/amount pair is needed

      ActiveRecord::Base.transaction do
        dunning_campaign = organization.dunning_campaigns.create!(
          applied_to_organization: params[:applied_to_organization],
          code: params[:code],
          days_between_attempts: params[:days_between_attempts],
          max_attempts: params[:max_attempts],
          name: params[:name],
          description: params[:description],
          thresholds_attributes: params[:thresholds].map(&:to_h)
        )

        # TODO: If the dunning campaign is applied to the organization, we need to remove the flag from all other dunning campaigns.

        result.dunning_campaign = dunning_campaign
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :organization, :params
  end
end
