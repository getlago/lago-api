# frozen_string_literal: true

module DunningCampaigns
  class ProcessAttemptService < BaseService
    def initialize(customer:, dunning_campaign_threshold:)
      @customer = customer
      @dunning_campaign_threshold = dunning_campaign_threshold
      @dunning_campaign = dunning_campaign_threshold.dunning_campaign
      @organization = customer.organization

      super
    end

    def call
      return result unless organization.auto_dunning_enabled?
      return result unless applicable_dunning_campaign?
      return result unless dunning_campaign_threshold_reached?
      return result unless days_between_attempts_passed?
      return result if dunning_campaign_completed?

      ActiveRecord::Base.transaction do
        payment_request_result = PaymentRequests::CreateService.call(
          organization:,
          params: {
            external_customer_id: customer.external_id,
            lago_invoice_ids: overdue_invoices.pluck(:id)
          }
        ).raise_if_error!

        customer.increment(:last_dunning_campaign_attempt)
        customer.last_dunning_campaign_attempt_at = Time.zone.now
        customer.save!

        result.customer = customer
        result.payment_request = payment_request_result.payment_request
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :customer, :dunning_campaign, :dunning_campaign_threshold, :organization

    def applicable_dunning_campaign?
      return false if customer.exclude_from_dunning_campaign?

      custom_campaign = customer.applied_dunning_campaign
      default_campaign = organization.applied_dunning_campaign

      custom_campaign == dunning_campaign || (!custom_campaign && default_campaign == dunning_campaign)
    end

    def dunning_campaign_threshold_reached?
      overdue_invoices.sum(:total_amount_cents) >= dunning_campaign_threshold.amount_cents
    end

    def days_between_attempts_passed?
      return true unless customer.last_dunning_campaign_attempt_at

      (customer.last_dunning_campaign_attempt_at + dunning_campaign.days_between_attempts.days).past?
    end

    def dunning_campaign_completed?
      customer.last_dunning_campaign_attempt >= dunning_campaign.max_attempts
    end

    def overdue_invoices
      customer
        .invoices
        .payment_overdue
        .where(currency: dunning_campaign_threshold.currency)
    end
  end
end
