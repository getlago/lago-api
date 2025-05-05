# frozen_string_literal: true

module Invoices
  class VoidService < BaseService
    def initialize(invoice:, params:)
      @invoice = invoice
      @generate_credit_note = ActiveModel::Type::Boolean.new.cast(params[:generate_credit_note])
      @refund_amount = params[:refund_amount].to_i
      @credit_amount = params[:credit_amount].to_i
      super
    end

    def call
      return result.not_found_failure!(resource: "invoice") if invoice.nil?
      return result.not_allowed_failure!(code: "not_voidable") if !invoice.voidable? && !explicit_void_intent?

      result.invoice = invoice

      ActiveRecord::Base.transaction do
        invoice.payment_overdue = false if invoice.payment_overdue?
        invoice.void!

        flag_lifetime_usage_for_refresh
      end

      invoice.credits.each do |credit|
        if credit.credit_note_id.present?
          res = CreditNotes::RecreditService.call(credit:)
          Rails.logger.warn("Recrediting credit #{credit.id} failed for invoice #{invoice.id}") unless res.success?
        end

        if credit.applied_coupon_id.present?
          res = Coupons::VoidAndRestoreAppliedCouponService.call(credit:)
          Rails.logger.warn("Voiding applied coupon for credit #{credit.id} failed for invoice #{invoice.id}") unless res.success?
        end
      end

      invoice.wallet_transactions.each do |wallet_transaction|
        res = WalletTransactions::RecreditService.call(wallet_transaction:)

        unless res.success?
          Rails.logger.warn("Recrediting wallet transaction #{wallet_transaction.id} failed for invoice #{invoice.id}")
        end
      end

      SendWebhookJob.perform_later("invoice.voided", result.invoice)
      Invoices::ProviderTaxes::VoidJob.perform_later(invoice:)
      Integrations::Aggregator::Invoices::Hubspot::UpdateJob.perform_later(invoice:) if invoice.should_update_hubspot_invoice?

      result
    rescue AASM::InvalidTransition => _e
      result.not_allowed_failure!(code: "not_voidable")
    end

    private

    attr_reader :invoice, :generate_credit_note, :refund_amount, :credit_amount

    def explicit_void_intent?
      generate_credit_note || refund_amount.positive? || credit_amount.positive?
    end

    def flag_lifetime_usage_for_refresh
      LifetimeUsages::FlagRefreshFromInvoiceService.call(invoice:).raise_if_error!
    end
  end
end
