# frozen_string_literal: true

module Invoices
  class VoidService < BaseService
    def initialize(invoice:)
      @invoice = invoice
      super
    end

    activity_loggable(
      action: "invoice.voided",
      record: -> { invoice }
    )

    def call
      return result.not_found_failure!(resource: "invoice") unless invoice
      return result.not_allowed_failure!(code: "not_voidable") if invoice.voided?

      ActiveRecord::Base.transaction do
        invoice.payment_overdue = false if invoice.payment_overdue?
        invoice.void!

        flag_lifetime_usage_for_refresh

        # Process credits within the same transaction
        invoice.credits.each do |credit|
          # Handle credits related to applied coupons
          if credit.applied_coupon_id.present?
            AppliedCoupons::RecreditService.call!(credit:)
          end

          # Handle credits related to credit notes
          if credit.credit_note_id.present?
            CreditNotes::RecreditService.call!(credit:)
          end
        end

        # Process wallet transactions within the same transaction
        invoice.wallet_transactions.outbound.each do |wallet_transaction|
          WalletTransactions::RecreditService.call!(wallet_transaction:)
        end
      end

      # Only proceed with webhooks and jobs if the transaction was successful
      unless invoice.voided?
        return result.service_failure!(code: "void_operation_failed", message: "Failed to void the invoice")
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
