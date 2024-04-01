# frozen_string_literal: true

module Invoices
  class LoseDisputeService < BaseService
    def initialize(invoice:)
      @invoice = invoice
      super
    end

    def call
      return result.not_found_failure!(resource: 'invoice') if invoice.nil?

      result.invoice = invoice

      invoice.mark_as_dispute_lost!

      if invoice.organization.webhook_endpoints.any?
        SendWebhookJob.perform_later('invoice.payment_dispute_lost', result.invoice)
      end

      result
    rescue ActiveRecord::RecordInvalid => _e
      result.not_allowed_failure!(code: 'not_disputable')
    end

    private

    attr_reader :invoice
  end
end
