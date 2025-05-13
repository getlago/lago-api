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

    # Distributes a given amount proportionally across the invoice fees
    # Returns an array of items with fee_id and amount_cents
    def distribute_amount_to_items(total_amount)
      return [] if total_amount.zero?

      # Get all fees from the invoice that have remaining creditable amount
      fees = invoice.fees.to_a.select { |fee| fee.creditable_amount_cents.positive? }

      # Calculate total remaining creditable amount across all fees
      total_creditable_amount = fees.sum(&:creditable_amount_cents)

      # If there are no fees with creditable amount, return empty array
      return [] if fees.empty? || total_creditable_amount.zero?

      # Cap the total amount to the total creditable amount if needed
      actual_total_amount = [total_amount, total_creditable_amount].min

      # Calculate proportional amount for each fee based on remaining creditable amount
      items = []
      remaining_amount = actual_total_amount

      # Process all fees except the last one
      fees[0...-1].each do |fee|
        # Calculate the proportion of this fee's creditable amount relative to the total
        proportion = fee.creditable_amount_cents.to_f / total_creditable_amount

        # Calculate the amount for this fee, capped at its creditable amount
        fee_amount = [
          (actual_total_amount * proportion).round,
          fee.creditable_amount_cents
        ].min

        # Add the item if the amount is positive
        if fee_amount.positive?
          items << {
            fee_id: fee.id,
            amount_cents: fee_amount
          }
          remaining_amount -= fee_amount
        end
      end

      # Assign the remaining amount to the last fee, capped at its creditable amount
      last_fee = fees.last
      if last_fee && remaining_amount.positive?
        last_fee_amount = [remaining_amount, last_fee.creditable_amount_cents].min

        if last_fee_amount.positive?
          items << {
            fee_id: last_fee.id,
            amount_cents: last_fee_amount
          }
        end
      end

      items
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

      # Calculate the total amount to be credited/refunded
      total_amount = credit_amount + refund_amount

      if total_amount > invoice.total_amount_cents
        return result.single_validation_failure!(
          field: :credit_refund_amount,
          error_code: "total_amount_exceeds_invoice_amount"
        )
      end

      # Generate items with proportional distribution of the credit/refund amount
      items = distribute_amount_to_items(total_amount)

      result = CreditNotes::CreateService.call(
        invoice: invoice,
        reason: :other,
        description: "Credit note created due to voided invoice",
        credit_amount_cents: credit_amount,
        refund_amount_cents: refund_amount,
        items: items
      )

      # Calculate remaining amount to be voided in a credit note
      total_invoice_amount = invoice.total_amount_cents
      remaining_amount = total_invoice_amount - credit_amount - refund_amount
      if remaining_amount.positive?
        # Generate items for the remaining amount
        remaining_items = distribute_amount_to_items(remaining_amount)

        credit_note_to_void = CreditNotes::CreateService.call(
          invoice: invoice,
          reason: :other,
          description: "Credit note created due to voided invoice",
          credit_amount_cents: remaining_amount,
          items: remaining_items
        )
        if credit_note_to_void.success?
          CreditNotes::VoidService.call(credit_note: credit_note_to_void.credit_note)
        end
      end

      result
    end
  end
end
