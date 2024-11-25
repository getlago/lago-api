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
        update_dunning_campaign_attributes
        handle_thresholds if params.key?(:thresholds)
        handle_applied_to_organization_update if params.key?(:applied_to_organization)

        dunning_campaign.save!
      end

      result.dunning_campaign = dunning_campaign
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :dunning_campaign, :organization, :params

    def update_dunning_campaign_attributes
      dunning_campaign.assign_attributes(permitted_attributes)
    end

    def permitted_attributes
      params.slice(:name, :code, :description, :days_between_attempts, :max_attempts)
    end

    def handle_thresholds
      input_threshold_ids = params[:thresholds].map { |t| t[:id] }.compact

      # Delete thresholds not included in the payload
      dunning_campaign.thresholds.where.not(id: input_threshold_ids).discard_all

      # Update or create new thresholds from the input
      params[:thresholds].each do |threshold_input|
        dunning_campaign.thresholds.find_or_initialize_by(
          id: threshold_input[:id]
        ).update!(
          amount_cents: threshold_input[:amount_cents],
          currency: threshold_input[:currency]
        )
      end
    end


    def handle_applied_to_organization_update
      dunning_campaign.applied_to_organization = params[:applied_to_organization]

      return unless dunning_campaign.applied_to_organization_changed?

      organization
        .dunning_campaigns
        .applied_to_organization
        .update_all(applied_to_organization: false) # rubocop:disable Rails/SkipsModelValidations

      organization.reset_customers_last_dunning_campaign_attempt
    end
  end
end
