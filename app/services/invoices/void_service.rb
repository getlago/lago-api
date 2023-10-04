# frozen_string_literal: true

module Invoices
  class VoidService < BaseService
    def initialize(invoice:)
      @invoice = invoice
      super
    end

    def call
      return result.not_found_failure!(resource: 'invoice') if invoice.nil?

      result.invoice = invoice

      begin
        invoice.void!

        invoice.credits.each do |credit|
          CreditNotes::RecreditService.new(credit:).call
        end

        invoice.wallet_transactions.each do |wallet_transaction|
          WalletTransactions::RecreditService.new(wallet_transaction:).call
        end

        SendWebhookJob.perform_later('invoice.voided', result.invoice) if invoice.organization.webhook_endpoints.any?
      rescue AASM::InvalidTransition => _e
        return result.not_allowed_failure!(code: 'not_voidable')
      end

      result
    end

    private

    attr_reader :invoice
  end
end
