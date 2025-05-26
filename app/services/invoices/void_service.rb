# frozen_string_literal: true

# Service responsible for voiding invoices and handling the associated credit/refund process.
#
# When an invoice is voided, this service:
# 1. Validates if the invoice can be voided
# 2. Processes any existing credits and wallet transactions
# 3. Optionally creates credit notes for the voided amount
#
# The service accepts the following parameters:
# @param invoice [Invoice] The invoice to be voided
# @param params [Hash] Additional parameters for the void process
# @option params [Boolean] :generate_credit_note Whether to create a credit note for the voided amount
# @option params [Integer] :credit_amount The amount to be credited (in cents)
# @option params [Integer] :refund_amount The amount to be refunded (in cents)
#
# The credit_amount and refund_amount parameters allow flexibility in how the voided amount is handled:
# - The total processed amount (credit + refund) cannot exceed the invoice total
# - Each amount is validated against available limits (creditable/refundable amounts)
# - The amounts determine which fees will be included in the credit note
#
# Example:
#   Invoices::VoidService.call(
#     invoice: invoice,
#     params: {
#       generate_credit_note: true,
#       credit_amount: 5000,    # $50.00 to be credited
#       refund_amount: 3000     # $30.00 to be refunded
#     }
#   )

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
        if credit.credit_note_id.present?
          res = CreditNotes::RecreditService.call(credit:)
          Rails.logger.warn("Recrediting credit #{credit.id} failed for invoice #{invoice.id}") unless res.success?
        end

        if credit.applied_coupon_id.present?
          res = AppliedCoupons::VoidAndRestoreService.call(credit:)
          Rails.logger.warn("Voiding applied coupon for credit #{credit.id} failed for invoice #{invoice.id}") unless res.success?
        end
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

    def select_deductible_fee(total_amount)
      fees = invoice.fees.to_a.select { |fee| fee.creditable_amount_cents.positive? }
      return [] if fees.empty?
      return [] if fees.sum(&:creditable_amount_cents).zero?

      fees.sort_by! { |fee| fee.creditable_amount_cents }

      deductible_fees = []
      deducted_amount = 0.0

      fees.each do |fee|
        return deductible_fees if deducted_amount > total_amount
        deducted_amount += fee.creditable_amount_cents
        deductible_fees << fee.id
      end

      deductible_fees
    end

    def create_credit_note
      available_credit_amount = invoice.creditable_amount_cents
      available_refund_amount = invoice.refundable_amount_cents

      if credit_amount > available_credit_amount
        return result.single_validation_failure!(field: :credit_amount, error_code: "credit_amount_exceeds_available_amount")
      end

      if refund_amount > available_refund_amount
        return result.single_validation_failure!(field: :refund_amount, error_code: "refund_amount_exceeds_available_amount")
      end

      total_amount = credit_amount + refund_amount

      if total_amount > invoice.total_amount_cents
        return result.single_validation_failure!(
          field: :credit_refund_amount,
          error_code: "total_amount_exceeds_invoice_amount"
        )
      end

      deductible_items = []
      deductible_fees = select_deductible_fee_ids(total_amount)
      deductible_fees.each do |fee|
        deductible_items << {
          fee_id: fee.id,
          amount_cents: fee.creditable_amount_cents
        }
      end

      result = CreditNotes::CreateService.call(
        invoice: invoice,
        reason: :other,
        description: "Credit note created due to voided invoice",
        credit_amount_cents: credit_amount,
        refund_amount_cents: refund_amount,
        items: deductible_items
      )

      # Calculate remaining amount to be voided in a credit note
      total_invoice_amount = invoice.total_amount_cents
      total_deductible_fees_amount = deductible_items.sum { |item| item[:amount_cents] }
      remaining_amount = total_invoice_amount - credit_amount - refund_amount - total_deductible_fees_amount

      if remaining_amount.positive?
        credit_note_to_void = CreditNotes::CreateService.call(
          invoice: invoice,
          reason: :other,
          description: "Credit note created due to voided invoice",
          credit_amount_cents: remaining_amount,
          items: [{
            fee_id: invoice.fees.first.id,
            amount_cents: remaining_amount
          }]
        )

        if credit_note_to_void.success?
          CreditNotes::VoidService.call(credit_note: credit_note_to_void.credit_note)
        end
      end

      result
    end
  end
end
