# frozen_string_literal: true

module Invoices
  class VoidService < BaseService
    def initialize(invoice:)
      @invoice = invoice
      super
    end

    def call
      return result.not_found_failure!(resource: 'invoice') unless invoice
      return result.not_allowed_failure!(code: 'invoice_already_voided') if invoice.voided?

      ActiveRecord::Base.transaction do
        invoice.payment_overdue = false if invoice.payment_overdue?
        invoice.void!

        flag_lifetime_usage_for_refresh
      end

      # Only process credits if the invoice was successfully voided
      if invoice.voided?
        invoice.credits.each do |credit|
          # Handle credits related to applied coupons
          if credit.applied_coupon_id.present?
            recredit_result = AppliedCoupons::RecreditService.call(credit:)
            Rails.logger.warn("Recrediting applied coupon for credit #{credit.id} failed for invoice #{invoice.id}") unless recredit_result.success?
          end

          # Handle credits related to credit notes
          if credit.credit_note_id.present?
            res = CreditNotes::RecreditService.call(credit:)
            Rails.logger.warn("Recrediting credit #{credit.id} failed for invoice #{invoice.id}") unless res.success?
          end
        end

        invoice.wallet_transactions.outbound.each do |wallet_transaction|
          res = WalletTransactions::RecreditService.call(wallet_transaction:)

          unless res.success?
            Rails.logger.warn("Recrediting wallet transaction #{wallet_transaction.id} failed for invoice #{invoice.id}")
          end
        end
      end

      result.invoice = invoice
      SendWebhookJob.perform_later("invoice.voided", result.invoice)
      Invoices::ProviderTaxes::VoidJob.perform_later(invoice:)
      Integrations::Aggregator::Invoices::Hubspot::UpdateJob.perform_later(invoice:) if invoice.should_update_hubspot_invoice?

      result
    rescue AASM::InvalidTransition => _e
      result.not_allowed_failure!(code: "not_voidable")
    end

    private

    attr_reader :invoice

    def flag_lifetime_usage_for_refresh
      LifetimeUsages::FlagRefreshFromInvoiceService.call(invoice:).raise_if_error!
    end
  end
end
