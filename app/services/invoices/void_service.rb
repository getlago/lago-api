# frozen_string_literal: true

module Invoices
  class VoidService < BaseService
    def initialize(invoice:, params: {})
      @invoice = invoice
      @params = params
      @generate_credit_note = ActiveModel::Type::Boolean.new.cast(params[:generate_credit_note])
      @refund_amount = params[:refund_amount].to_i
      @credit_amount = params[:credit_amount].to_i
      super
    end

    activity_loggable(
      action: "invoice.voided",
      record: -> { invoice }
    )

    def call
      return result.not_found_failure!(resource: "invoice") unless invoice
      return result.not_allowed_failure!(code: "not_voidable") if invoice.voided?
      return result.not_allowed_failure!(code: "not_voidable") if !invoice.voidable? && !explicit_void_intent?
      unless validate_credit_note_amounts!
        return result.single_validation_failure!(
          field: :credit_refund_amount,
          error_code: "total_amount_exceeds_invoice_amount"
        )
      end

      ActiveRecord::Base.transaction do
        invoice.payment_overdue = false if invoice.payment_overdue?
        if invoice.may_void?
          invoice.void!
        else
          invoice.force_void!
        end

        flag_lifetime_usage_for_refresh

        invoice.credits.each do |credit|
          AppliedCoupons::RecreditService.call!(credit:) if credit.applied_coupon_id.present?
          CreditNotes::RecreditService.call!(credit:) if credit.credit_note_id.present?
        end

        invoice.wallet_transactions.outbound.each do |wallet_transaction|
          WalletTransactions::RecreditService.call!(wallet_transaction:)
        end

        if generate_credit_note
          create_credit_notes!
        end
      end

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

    attr_reader :invoice, :params, :generate_credit_note, :credit_amount, :refund_amount

    def flag_lifetime_usage_for_refresh
      LifetimeUsages::FlagRefreshFromInvoiceService.call(invoice:).raise_if_error!
    end

    def explicit_void_intent?
      params.key?(:generate_credit_note)
    end

    def validate_credit_note_amounts!
      return true unless generate_credit_note

      return false if credit_amount > invoice.creditable_amount_cents
      return false if refund_amount > invoice.refundable_amount_cents
      return false if (credit_amount + refund_amount) > invoice.creditable_amount_cents

      true
    end

    def create_credit_notes!
      total_amount = credit_amount + refund_amount

      return result if total_amount.zero?

      estimate_result = estimate_credit_note_for_target_credit(invoice: invoice, target_credit_cents: total_amount)
      items = estimate_result.success? ? estimate_result.credit_note.items.map { |item| {fee_id: item.fee_id, amount_cents: item.amount_cents} } : []

      result = CreditNotes::CreateService.call!(
        invoice: invoice,
        reason: :other,
        description: "Credit note created due to voided invoice #{invoice.id}",
        credit_amount_cents: estimate_result.credit_note.credit_amount_cents - refund_amount,
        refund_amount_cents: refund_amount,
        items: items
      )

      remaining_amount = invoice.reload.creditable_amount_cents
      if remaining_amount.positive?
        estimate_result = estimate_credit_note_for_target_credit(invoice: invoice, target_credit_cents: remaining_amount)
        items = estimate_result.success? ? estimate_result.credit_note.items.map { |item| {fee_id: item.fee_id, amount_cents: item.amount_cents} } : []

        credit_note_to_void = CreditNotes::CreateService.call!(
          invoice: invoice,
          reason: :other,
          description: "Credit note created due to voided invoice #{invoice.id}",
          credit_amount_cents: estimate_result.credit_note.credit_amount_cents,
          items: items
        )

        if credit_note_to_void.success?
          CreditNotes::VoidService.call!(credit_note: credit_note_to_void.credit_note)
        end
      end

      result
    end

    def estimate_credit_note_for_target_credit(invoice:, target_credit_cents:)
      base_total = invoice.sub_total_including_taxes_amount_cents.to_f
      ratio = target_credit_cents.to_f / base_total

      items = invoice.fees.map do |fee|
        {
          fee_id: fee.id,
          amount_cents: (fee.precise_amount_cents * ratio)
        }
      end

      CreditNotes::EstimateService.call!(invoice: invoice, items: items)
    end
  end
end
