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
        dunning_campaign.name = params[:name] if params.key?(:name)
        dunning_campaign.code = params[:code] if params.key?(:code)
        dunning_campaign.description = params[:description] if params.key?(:description)
        dunning_campaign.days_between_attempts = params[:days_between_attempts] if params.key?(:days_between_attempts)
        dunning_campaign.max_attempts = params[:max_attempts] if params.key?(:max_attempts)

        handle_thresholds if params.key?(:thresholds)

        unless params[:applied_to_organization].nil?
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
  end
end
