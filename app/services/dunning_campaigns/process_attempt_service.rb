# frozen_string_literal: true

module DunningCampaigns
  class ProcessAttemptService < BaseService
    def initialize(customer:, dunning_campaign_threshold:)
      @customer = customer
      @dunning_campaign_threshold = dunning_campaign_threshold
      super
    end

    def call
      return unless organization.auto_dunning_enabled?
      # TODO: ensure the campaign is still applicable to customer
      # TODO: ensure campaign thresold is still meet
      # TODO: ensure customer does not use all attempts
      # TODO: ensure time now > last attempt + delay

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

    attr_reader :customer, :dunning_campaign_threshold

    def organization
      customer.organization
    end

    def dunning_campaign
      dunning_campaign_threshold.dunning_campaign
    end

    def overdue_invoices
      customer
        .invoices
        .payment_overdue
        .where(currency: dunning_campaign_threshold.currency)
    end
  end
end
