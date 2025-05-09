# frozen_string_literal: true

module Invoices
  class VoidService < BaseService
    def initialize(invoice:, params:)
      @invoice = invoice
      @params = params
      @generate_credit_note = ActiveModel::Type::Boolean.new.cast(params[:generate_credit_note])
      @refund_amount = params[:refund_amount].to_i
      @credit_amount = params[:credit_amount].to_i
      super
    end

    def call
      return result.not_found_failure!(resource: "invoice") if invoice.nil?
      # return result.not_allowed_failure!(code: "not_voidable") if invoice.voided?
      return result.not_allowed_failure!(code: "not_voidable") if !invoice.voidable? && !explicit_void_intent?

      result.invoice = invoice

      ActiveRecord::Base.transaction do
        invoice.payment_overdue = false if invoice.payment_overdue?
        if invoice.may_void?
          invoice.void!
        else
          invoice.force_void!
        end

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

      if generate_credit_note
        create_credit_note_result = create_credit_note
        unless create_credit_note_result.success?
          Rails.logger.warn("Creating credit note for invoice #{invoice.id} failed: #{create_credit_note_result.error}")
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

    attr_reader :invoice, :params, :generate_credit_note, :credit_amount, :refund_amount

    def flag_lifetime_usage_for_refresh
      LifetimeUsages::FlagRefreshFromInvoiceService.call(invoice:).raise_if_error!
    end

    def explicit_void_intent?
      params.key?(:generate_credit_note)
    end

    def create_credit_note
      # Calculate valid amounts based on invoice limits
      available_credit_amount = invoice.creditable_amount_cents
      available_refund_amount = invoice.refundable_amount_cents

      if credit_amount > available_credit_amount
        return result.single_validation_failure!(field: :credit_amount, error_code: "credit_amount_exceeds_available_amount")
      end

      if refund_amount > available_refund_amount
        return result.single_validation_failure!(field: :refund_amount, error_code: "refund_amount_exceeds_available_amount")
      end

      result = CreditNotes::CreateService.call(
        invoice: invoice,
        reason: :other,
        description: "Credit note created due to voided invoice",
        credit_amount_cents: credit_amount,
        refund_amount_cents: refund_amount
      )

      # Calculate remaining amount to be voided in a credit note
      total_invoice_amount = invoice.total_amount_cents
      remaining_amount = total_invoice_amount - credit_amount - refund_amount
      if remaining_amount.positive?
        credit_note_to_void = CreditNotes::CreateService.call(
          invoice: invoice,
          reason: :other,
          description: "Credit note created due to voided invoice",
          refund_amount_cents: remaining_amount
        )
        if credit_note_to_void.success?
          CreditNotes::VoidService.call(credit_note: credit_note_to_void.credit_note)
        end
      end

      result
    end
  end
end
