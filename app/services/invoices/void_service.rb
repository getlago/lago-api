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
      return result.not_allowed_failure!(code: "not_voidable") if invoice.voided?
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

      # Create credit note if requested
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

    attr_reader :invoice, :generate_credit_note, :refund_amount, :credit_amount, :params

    def explicit_void_intent?
      params.key?(:generate_credit_note)
    end

    def flag_lifetime_usage_for_refresh
      LifetimeUsages::FlagRefreshFromInvoiceService.call(invoice:).raise_if_error!
    end

    def create_credit_note
      # Calculate valid amounts based on invoice limits
      available_credit_amount = invoice.creditable_amount_cents
      available_refund_amount = invoice.refundable_amount_cents

      # Ensure amounts don't exceed available amounts
      validated_credit_amount = [credit_amount, available_credit_amount].min
      validated_refund_amount = [refund_amount, available_refund_amount].min

      # Calculate remaining amount to be voided in wallet
      total_invoice_amount = invoice.total_amount_cents
      remaining_amount = total_invoice_amount - validated_credit_amount - validated_refund_amount

      # Create credit note if there's any amount to credit or refund
      credit_note_result = nil
      if validated_credit_amount.positive? || validated_refund_amount.positive?
        credit_note_result = CreditNotes::CreateService.call(
          invoice: invoice,
          reason: :other,
          description: "Credit note created due to voided invoice",
          credit_amount_cents: validated_credit_amount,
          refund_amount_cents: validated_refund_amount
        )
      end

      # Create voided wallet transaction for remaining amount if positive
      if remaining_amount.positive?
        create_voided_wallet_transaction(remaining_amount, credit_note_result&.credit_note)
      end

      # Return the credit note result or a success result if no credit note was created
      credit_note_result || BaseService::Result.new
    end

    def create_voided_creedits(amount, credit_note)
      # TODO fazer coisas aqui
    end
  end
end
