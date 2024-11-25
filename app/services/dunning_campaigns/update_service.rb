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
        dunning_campaign.assign_attributes(permitted_attributes)
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

    def permitted_attributes
      params.slice(:name, :code, :description, :days_between_attempts, :max_attempts)
    end

    def handle_thresholds
      thresholds_updated = false

      input_threshold_ids = params[:thresholds].map { |t| t[:id] }.compact

      # Delete thresholds not included in the payload
      discarded_thresholds = dunning_campaign
        .thresholds
        .where.not(id: input_threshold_ids)
        .discard_all

      thresholds_updated = discarded_thresholds.present?

      # Update or create new thresholds from the input
      params[:thresholds].each do |threshold_input|
        threshold = dunning_campaign.thresholds.find_or_initialize_by(
          id: threshold_input[:id]
        )

        threshold.assign_attributes(threshold_input.slice(:amount_cents, :currency))

        thresholds_updated ||= threshold.changed? && threshold.persisted?
        threshold.save!
      end

      reset_customers_if_no_threshold_match if thresholds_updated
    end

    def reset_customers_if_no_threshold_match
      customers_applied_campaign = organization
        .customers
        .with_dunning_campaign_not_completed
        .where(applied_dunning_campaign: dunning_campaign)

      customers_fallback_campaign = organization
        .customers
        .falling_back_to_default_dunning_campaign
        .with_dunning_campaign_not_completed

      customers_to_reset = customers_applied_campaign.or(customers_fallback_campaign)

      customers_to_reset
        .includes(:invoices)
        .where(invoices: {payment_overdue: true}).each do |customer|
          threshold_matches = dunning_campaign.thresholds.any? do |threshold|
            threshold.currency == customer.currency &&
              customer.overdue_balance_cents >= threshold.amount_cents
          end

          unless threshold_matches
            customer.update!(
              last_dunning_campaign_attempt: 0,
              last_dunning_campaign_attempt_at: nil
            )
          end
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
