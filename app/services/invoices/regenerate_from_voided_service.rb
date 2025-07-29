# frozen_string_literal: true

module Invoices
  class RegenerateFromVoidedService < BaseService
    Result = BaseResult[:invoice]
    def initialize(voided_invoice:, fees_params:)
      @voided_invoice = voided_invoice
      @fees_params = fees_params

      super
    end

    activity_loggable(
      action: "invoice.regenerated_from_voided",
      record: -> { voided_invoice }
    )

    def call
      return result.not_found_failure!(resource: "invoice") unless voided_invoice
      invoice = nil

      ActiveRecord::Base.transaction do
        invoice = create_regenerated_invoice
        create_invoice_subscription(invoice) if invoice.invoice_type == "subscription"
        process_fees(invoice)
        adjust_fees(invoice)
        Invoices::ApplyInvoiceCustomSectionsService.call(invoice: invoice)
        invoice.fees_amount_cents = invoice.fees.sum(:amount_cents)
        invoice.sub_total_excluding_taxes_amount_cents = invoice.fees.sum(:amount_cents)

        Credits::ProgressiveBillingService.call(invoice:)
        Credits::AppliedCouponsService.call(invoice: invoice) if should_create_coupon_credit?(invoice)

        Invoices::ComputeTaxesAndTotalsService.call(invoice:, finalizing: true)
        create_credit_note_credit(invoice) if should_create_credit_note_credit?(invoice)
        create_applied_prepaid_credit(invoice) if should_create_applied_prepaid_credit?(invoice)
        invoice.payment_status = invoice.total_amount_cents.positive? ? :pending : :succeeded
        Invoices::TransitionToFinalStatusService.call(invoice: invoice)
        invoice.save!
      end

      result.invoice = invoice.reload
      result
    end

    private

    attr_reader :voided_invoice, :fees_params

    def should_create_credit_note_credit?(invoice)
      return false unless invoice.total_amount_cents&.positive?

      true
    end

    def should_create_coupon_credit?(invoice)
      return false unless invoice.fees_amount_cents&.positive?

      true
    end

    def should_create_applied_prepaid_credit?(invoice)
      return false unless wallet&.active?
      return false unless invoice.total_amount_cents&.positive?

      wallet.balance.positive?
    end

    def create_applied_prepaid_credit(invoice)
      prepaid_credit_result = Credits::AppliedPrepaidCreditService.call(invoice:, wallet:)
      prepaid_credit_result.raise_if_error!

      refresh_amounts(invoice, credit_amount_cents: prepaid_credit_result.prepaid_credit_amount_cents)
    end

    def create_credit_note_credit(invoice)
      credit_result = Credits::CreditNoteService.new(invoice:).call
      credit_result.raise_if_error!

      refresh_amounts(invoice ,credit_amount_cents: credit_result.credits.sum(&:amount_cents)) if credit_result.credits
    end

    def refresh_amounts(invoice ,credit_amount_cents:)
      invoice.total_amount_cents -= credit_amount_cents
    end

    def create_regenerated_invoice
      generating_result = Invoices::CreateGeneratingService.call!(
        customer: voided_invoice.customer,
        invoice_type: voided_invoice.invoice_type,
        currency: voided_invoice.currency,
        datetime: voided_invoice.created_at,
      )
      invoice = generating_result.invoice
      invoice.update(voided_invoice_id: voided_invoice.id)
      invoice
    end

    def create_invoice_subscription(invoice)
      voided_invoice.invoice_subscriptions.update_all(regenerated_invoice_id: invoice.id)
      voided_invoice.invoice_subscriptions.each do |invoice_subscription|
        invoice_subscription.dup.tap do |dup_invoice_subscription|
          dup_invoice_subscription.invoice = invoice
          dup_invoice_subscription.regenerated_invoice_id = nil
          dup_invoice_subscription.save!
        end
      end
    end

    def adjust_fees(invoice)
      invoice.fees.each do |fee|
        if fee.fee_type == "charge"
          properties = fee.charge_filter&.properties || fee.charge.properties
          result = Fees::InitFromAdjustedChargeFeeService.call(
            adjusted_fee: fee.adjusted_fee,
            boundaries: fee.properties,
            properties: properties
          )
          adjusted_fee = result.fee
          attrs = adjusted_fee.attributes.slice(
            "invoice_display_name",
            "charge_id",
            "subscription_id",
            "units",
            "unit_amount_cents",
            "precise_unit_amount",
            "amount_cents",
            "precise_amount_cents",
            "amount_details",
            "charge_filter"
          )
          fee.assign_attributes(attrs)
          fee.save!
        else
          adjusted_fee = fee.adjusted_fee
          fee.invoice_display_name = fee.adjusted_fee.invoice_display_name if adjusted_fee.invoice_display_name.present?
          fee.charge_id = adjusted_fee.charge_id if adjusted_fee.charge_id.present?
          fee.subscription_id = adjusted_fee.subscription_id if adjusted_fee.subscription_id.present?
          fee.units = adjusted_fee.units if adjusted_fee.units.present?

          units = fee.units
          subunit = invoice.total_amount.currency.subunit_to_unit
          unit_precise_amount_cents = if adjusted_fee.unit_precise_amount_cents.zero?
            fee.precise_unit_amount
          else
            adjusted_fee.unit_precise_amount_cents
          end


          fee.unit_amount_cents = unit_precise_amount_cents.round
          fee.precise_unit_amount = unit_precise_amount_cents.to_d / subunit
          fee.amount_cents = (units * unit_precise_amount_cents).round
          fee.precise_amount_cents = units * unit_precise_amount_cents
          fee.save!
        end
      end
    end

    def process_fees(invoice)
      fees_params.each do |fee_params|

        if !fee_params[:id].blank?
          voided_fee = voided_invoice.fees.find_by(id: fee_params[:id])
          dep_fee = duplicate_fee(voided_fee, fee_params, invoice) if voided_fee
        end

        adjusted_fee_params = {
          invoice_display_name: fee_params[:invoice_display_name],
          units: fee_params[:units],
          charge_id: fee_params[:charge_id],
          charge_filter_id: fee_params[:charge_filter_id],
          subscription_id: fee_params[:subscription_id]
        }
        adjusted_fee_params[:unit_precise_amount] = fee_params[:unit_amount_cents] if fee_params[:unit_amount_cents].present?
        adjusted_fee_params[:fee_id] = dep_fee.id if dep_fee

        AdjustedFees::CreateService.call(
          invoice: invoice,
          params: adjusted_fee_params
        )
      end
    end
    def duplicate_fee(voided_fee, fee_params, invoice)
      dup_fee = voided_fee.dup
      dup_fee.invoice = invoice
      dup_fee.payment_status = :pending
      dup_fee.taxes_amount_cents = 0
      dup_fee.taxes_precise_amount_cents = 0
      dup_fee.precise_coupons_amount_cents = 0
      dup_fee.taxes_base_rate = 0
      dup_fee.taxes_rate = 0
      dup_fee.save!
      dup_fee
    end

    def wallet
      return @wallet if defined? @wallet

      @wallet = voided_invoice.customer.wallets.active.first
    end
  end
end
