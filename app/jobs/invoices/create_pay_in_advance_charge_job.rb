# frozen_string_literal: true

module Invoices
  class CreatePayInAdvanceChargeJob < ApplicationJob
    queue_as "billing"

    retry_on Sequenced::SequenceError

    def perform(charge:, event:, timestamp:, invoice: nil)
      result = Invoices::CreatePayInAdvanceChargeService.call(charge:, event:, timestamp:, invoice:)
      return if result.success?

      result.raise_if_error! if invoice || result.invoice.nil? || !result.invoice.generating?

      # NOTE: retry the job with the already created invoice in a previous failed attempt
      self.class.set(wait: 3.seconds).perform_later(
        charge:,
        event:,
        timestamp:,
        invoice: result.invoice
      )
    end
  end
end
