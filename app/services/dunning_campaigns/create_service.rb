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
      return result.validation_failure!(errors: {thresholds: ["can't be blank"]}) if params[:thresholds].blank?

      ActiveRecord::Base.transaction do
        if params[:applied_to_organization]
          organization
            .dunning_campaigns
            .applied_to_organization
            .update_all(applied_to_organization: false) # rubocop:disable Rails/SkipsModelValidations

          # NOTE: Stop and reset existing campaigns.
          organization.customers.where(
            applied_dunning_campaign_id: nil,
            exclude_from_dunning_campaign: false
          ).update_all( # rubocop:disable Rails/SkipsModelValidations
            last_dunning_campaign_attempt: 0,
            last_dunning_campaign_attempt_at: nil
          )
        end

        dunning_campaign = organization.dunning_campaigns.create!(
          applied_to_organization: params[:applied_to_organization],
          code: params[:code],
          days_between_attempts: params[:days_between_attempts],
          max_attempts: params[:max_attempts],
          name: params[:name],
          description: params[:description],
          thresholds_attributes: params[:thresholds].map(&:to_h)
        )

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
