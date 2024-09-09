# frozen_string_literal: true

module Invoices
  class CreatePayInAdvanceChargeJob < ApplicationJob
    queue_as 'billing'

    retry_on Sequenced::SequenceError

    unique :until_executed, on_conflict: :log

    def perform(charge:, event:, timestamp:, invoice: nil)
      result = Invoices::CreatePayInAdvanceChargeService.call(charge:, event:, timestamp:, invoice:)
      return if result.success?
      # NOTE: We don't want a dead job for failed invoice due to the tax reason.
      #       This invoice should be in failed status and can be retried.
      return if tax_error?(result)

      result.raise_if_error! if invoice || result.invoice.nil? || !result.invoice.generating?

      # NOTE: retry the job with the already created invoice in a previous failed attempt
      self.class.set(wait: 3.seconds).perform_later(
        charge:,
        event:,
        timestamp:,
        invoice: result.invoice
      )
    end

    private

    def tax_error?(result)
      return false unless result.error.is_a?(BaseService::ValidationFailure)

      result.error&.messages&.dig(:tax_error)
    end
  end
end
