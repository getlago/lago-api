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
      return result.forbidden_failure! unless generate_credit_note_allowed?
      unless valid_credit_note_amounts?
        return result.single_validation_failure!(
          field: :credit_refund_amount,
          error_code: "total_amount_exceeds_invoice_amount"
        )
      end

      invoice.with_lock do
        return result.not_allowed_failure!(code: "not_voidable") if invoice.voided?

        invoice.void!
        flag_lifetime_usage_for_refresh

        invoice.credits.each do |credit|
          AppliedCoupons::RecreditService.call!(credit:) if credit.applied_coupon_id.present?
        end

        # when generate_credit_note, we count the wallet value on the creditable value
        # so we don't need to recredit the wallet
        if generate_credit_note
          create_credit_notes!
        else
          invoice.wallet_transactions.outbound.each do |wallet_transaction|
            WalletTransactions::RecreditService.call!(wallet_transaction:) if wallet_transaction.wallet.active?
          end
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

    def generate_credit_note_allowed?
      return true unless generate_credit_note
      License.premium?
    end

    def flag_lifetime_usage_for_refresh
      LifetimeUsages::FlagRefreshFromInvoiceService.call(invoice:).raise_if_error!
    end

    def valid_credit_note_amounts?
      return true unless generate_credit_note

      return false if credit_amount > invoice.creditable_amount_cents
      return false if refund_amount > invoice.refundable_amount_cents
      return false if (credit_amount + refund_amount) > invoice.creditable_amount_cents

      true
    end

    def create_credit_notes!
      total_amount = credit_amount + refund_amount

      unless total_amount.zero?
        estimate_result = estimate_credit_note_for_target_credit(invoice: invoice, target_credit_cents: total_amount)

        result = CreditNotes::CreateService.call!(
          invoice: invoice,
          reason: :other,
          description: "Credit note created due to voided invoice #{invoice.id}",
          credit_amount_cents: credit_amount,
          refund_amount_cents: refund_amount,
          items: estimate_result
        )
      end

      remaining_amount = invoice.reload.creditable_amount_cents.round
      if remaining_amount.positive?
        estimate_result = estimate_credit_note_for_remaining_credit(invoice:)
        estimate_result = CreditNotes::EstimateService.call!(invoice: invoice, items: estimate_result)

        credit_note_to_void = CreditNotes::CreateService.call!(
          invoice: invoice,
          reason: :other,
          description: "Credit note created due to voided invoice #{invoice.id}",
          credit_amount_cents: estimate_result.credit_note.credit_amount_cents,
          items: estimate_result.credit_note.items.map { |item| {fee_id: item.fee_id, amount_cents: item.amount_cents} }
        )

        CreditNotes::VoidService.call!(credit_note: credit_note_to_void.credit_note)
      end

      result
    end

    def estimate_credit_note_for_remaining_credit(invoice:)
      invoice.fees.filter_map do |fee|
        next unless fee.creditable_amount_cents.positive?

        {
          fee_id: fee.id,
          amount_cents: fee.creditable_amount_cents
        }
      end
    end

    def estimate_credit_note_for_target_credit(invoice:, target_credit_cents:)
      base_items = estimate_credit_note_for_remaining_credit(invoice:)
      base_total = credit_note_total_for_items(invoice:, items: base_items).to_f
      return [] if base_total.zero?

      ratio = target_credit_cents.to_f / base_total

      base_items.map do |item|
        {
          fee_id: item[:fee_id],
          amount_cents: (item[:amount_cents] * ratio)
        }
      end
    end

    def credit_note_total_for_items(invoice:, items:)
      taxes_result = CreditNotes::ApplyTaxesService.call(
        invoice:,
        items: items.map do |item|
          CreditNoteItem.new(fee_id: item[:fee_id], precise_amount_cents: item[:amount_cents])
        end
      )

      items.sum { |item| item[:amount_cents] } -
        taxes_result.coupons_adjustment_amount_cents +
        taxes_result.precise_taxes_amount_cents
    end
  end
end
