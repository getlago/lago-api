# frozen_string_literal: true

module Invoices
  class RetryService < BaseService
    Result = BaseResult[:invoice]

    def initialize(invoice:)
      @invoice = invoice

      super
    end

    def call
      return result.not_found_failure!(resource: "invoice") unless invoice

      # Cancelling a payment-gated subscription closes this invoice under the same row lock,
      # so the status is read again here rather than trusted from before the lock was taken.
      invoice.with_lock do
        if invoice.failed?
          reopen_for_retry
        else
          result.not_allowed_failure!(code: "invalid_status")
        end
      end

      if result.success?
        Invoices::ProviderTaxes::PullTaxesAndApplyJob.perform_later(invoice:)
        result.invoice = invoice
      end

      result
    end

    private

    attr_accessor :invoice

    def reopen_for_retry
      invoice.status = invoice.subscriptions.any?(&:gated?) ? :open : :pending
      invoice.tax_status = "pending"
      invoice.save!
    end
  end
end
