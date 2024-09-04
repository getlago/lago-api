# frozen_string_literal: true

module LifetimeUsages
  class RecalculateAndCheckService < BaseService
    def initialize(lifetime_usage:)
      @lifetime_usage = lifetime_usage

      super
    end

    def call
      LifetimeUsages::CalculateService.call(lifetime_usage:).raise_if_error!
      result = LifetimeUsages::UsageThresholds::CheckService.call(lifetime_usage:, progressive_billed_amount:).raise_if_error!
      usage_thresholds = result.passed_thresholds
      if usage_thresholds.any?
        usage_thresholds.each do |usage_threshold|
          SendWebhookJob.perform_later('subscription.usage_threshold_reached', subscription, usage_threshold:)
        end
        invoice_result = Invoices::ProgressiveBillingService.call(usage_thresholds:, lifetime_usage:)
        # If there is tax error, invoice is marked as failed and it can be retried manually
        invoice_result.raise_if_error! unless tax_error?(invoice_result)
        result.invoice = invoice_result.invoice
      end
      result
    end

    private

    attr_reader :lifetime_usage
    delegate :subscription, to: :lifetime_usage

    def progressive_billed_amount
      result = Subscriptions::ProgressiveBilledAmount.call(subscription:).raise_if_error!
      result.progressive_billed_amount
    end

    def tax_error?(fee_result)
      !fee_result.success? && fee_result&.error&.code == 'tax_error'
    end
  end
end
