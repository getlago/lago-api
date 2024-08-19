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

      ActiveRecord::Base.transaction do
        invoice.payment_overdue = false if invoice.payment_overdue?
        invoice.void!

        flag_lifetime_usage_for_refresh
      end

      invoice.credits.each do |credit|
        res = CreditNotes::RecreditService.call(credit:)
        Rails.logger.warn("Recrediting credit #{credit.id} failed for invoice #{invoice.id}") unless res.success?
      end

      invoice.wallet_transactions.each do |wallet_transaction|
        res = WalletTransactions::RecreditService.call(wallet_transaction:)

        unless res.success?
          Rails.logger.warn("Recrediting wallet transaction #{wallet_transaction.id} failed for invoice #{invoice.id}")
        end
      end

      SendWebhookJob.perform_later('invoice.voided', result.invoice)
      Invoices::ProviderTaxes::VoidJob.perform_later(invoice:)

      result
    rescue AASM::InvalidTransition => _e
      result.not_allowed_failure!(code: 'not_voidable')
    end

    private

    attr_reader :invoice

    def flag_lifetime_usage_for_refresh
      LifetimeUsages::FlagRefreshFromInvoiceService.call(invoice:).raise_if_error!
    end
  end
end
