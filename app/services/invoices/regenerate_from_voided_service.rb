# frozen_string_literal: true

module Invoices
  class RegenerateFromVoidedService < BaseService
    Result = BaseResult[:invoice]

    def initialize(voided_invoice:, fees_params:)
      @voided_invoice = voided_invoice
      @fees_params = fees_params
      @regenerated_invoice = nil
      super
    end

    activity_loggable(
      action: "invoice.regenerated",
      record: -> { voided_invoice }
    )

    def call
      return result.not_found_failure!(resource: "invoice") unless voided_invoice

      ActiveRecord::Base.transaction do
        create_regenerated_invoice
        create_invoice_subscriptions if regenerated_invoice.invoice_type == "subscription"
        process_fees
        adjust_fees
        Invoices::ApplyInvoiceCustomSectionsService.call(invoice: regenerated_invoice)
        regenerated_invoice.fees_amount_cents = regenerated_invoice.fees.sum(:amount_cents)
        regenerated_invoice.sub_total_excluding_taxes_amount_cents = regenerated_invoice.fees.sum(:amount_cents)

        # apply taxes credits and coupons
        Credits::ProgressiveBillingService.call(invoice: regenerated_invoice)
        Credits::AppliedCouponsService.call(invoice: regenerated_invoice) if should_create_coupon_credit?
        Invoices::ComputeTaxesAndTotalsService.call(invoice: regenerated_invoice, finalizing: true)
        create_credit_note_credit if should_create_credit_note_credit?
        create_applied_prepaid_credit if should_create_applied_prepaid_credit?
        regenerated_invoice.payment_status = regenerated_invoice.total_amount_cents.positive? ? :pending : :succeeded
        Invoices::TransitionToFinalStatusService.call(invoice: regenerated_invoice)
        regenerated_invoice.save!
      end

      result.invoice = regenerated_invoice
      result
    end

    private

    attr_accessor :regenerated_invoice
    attr_reader :voided_invoice, :fees_params

    def should_create_credit_note_credit?
      return false unless regenerated_invoice.total_amount_cents&.positive?

      true
    end

    def should_create_coupon_credit?
      return false unless regenerated_invoice.fees_amount_cents&.positive?

      true
    end

    def should_create_applied_prepaid_credit?
      return false unless wallet&.active?
      return false unless regenerated_invoice.total_amount_cents&.positive?

      wallet.balance.positive?
    end

    def wallet
      return @wallet if defined? @wallet

      @wallet = voided_invoice.customer.wallets.active.first
    end

    def create_applied_prepaid_credit
      prepaid_credit_result = Credits::AppliedPrepaidCreditService.call(invoice: regenerated_invoice, wallet:)
      prepaid_credit_result.raise_if_error!

      refresh_amounts(credit_amount_cents: prepaid_credit_result.prepaid_credit_amount_cents)
    end

    def create_credit_note_credit
      credit_result = Credits::CreditNoteService.new(invoice: regenerated_invoice).call
      credit_result.raise_if_error!

      refresh_amounts(credit_amount_cents: credit_result.credits.sum(&:amount_cents)) if credit_result.credits
    end

    def refresh_amounts(credit_amount_cents:)
      regenerated_invoice.total_amount_cents -= credit_amount_cents
    end

    def adjust_fees
      subunit = regenerated_invoice.total_amount.currency.subunit_to_unit

      regenerated_invoice.fees.each do |fee|
        adjusted_fee = fee.adjusted_fee
        next unless adjusted_fee

        if fee.fee_type == "charge"
          properties = fee.charge_filter&.properties || fee.charge.properties

          result = Fees::InitFromAdjustedChargeFeeService.call(
            adjusted_fee:,
            boundaries: fee.properties,
            properties:
          )

          updated = result.fee
          fee.assign_attributes(
            updated.attributes.slice(
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
          )
        else
          fee.invoice_display_name = adjusted_fee.invoice_display_name if adjusted_fee.invoice_display_name.present?
          fee.charge_id = adjusted_fee.charge_id if adjusted_fee.charge_id.present?
          fee.subscription_id = adjusted_fee.subscription_id if adjusted_fee.subscription_id.present?
          fee.units = adjusted_fee.units if adjusted_fee.units.present?

          units = fee.units.to_d

          if adjusted_fee.adjusted_units?
            unit_cents = fee.unit_amount_cents
            amount_cents = (units * unit_cents).round
            precise_unit_amount = unit_cents.to_f / subunit
          else
            unit_cents = adjusted_fee.unit_precise_amount_cents
            amount_cents = (units * unit_cents).round
            precise_unit_amount = unit_cents / subunit
          end

          fee.unit_amount_cents = unit_cents.round
          fee.precise_unit_amount = precise_unit_amount
          fee.amount_cents = amount_cents
          fee.precise_amount_cents = units * unit_cents
        end

        fee.save!
      end
    end

    def process_fees
      fees_params.each do |fee_params|
        if fee_params[:id].present?
          voided_fee = voided_invoice.fees.find_by(id: fee_params[:id])
          dep_fee = duplicate_fee(voided_fee) if voided_fee
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
          invoice: regenerated_invoice,
          params: adjusted_fee_params,
          preview: true
        )
      end
    end

    def duplicate_fee(voided_fee)
      dup_fee = voided_fee.dup
      dup_fee.invoice = regenerated_invoice
      dup_fee.payment_status = :pending
      dup_fee.taxes_amount_cents = 0
      dup_fee.taxes_precise_amount_cents = 0
      dup_fee.precise_coupons_amount_cents = 0
      dup_fee.taxes_base_rate = 0
      dup_fee.taxes_rate = 0
      dup_fee.save!
      dup_fee
    end

    def create_invoice_subscriptions
      voided_invoice.invoice_subscriptions.each do |subscription|
        subscription.update!(regenerated_invoice_id: regenerated_invoice.id)

        subscription.dup.tap do |dup|
          dup.invoice = regenerated_invoice
          dup.regenerated_invoice_id = nil
          dup.save!
        end
      end
    end

    def create_regenerated_invoice
      @regenerated_invoice = Invoices::CreateGeneratingService.call!(
        customer: voided_invoice.customer,
        invoice_type: voided_invoice.invoice_type,
        currency: voided_invoice.currency,
        datetime: voided_invoice.created_at
      ).invoice.tap do |invoice|
        invoice.update!(voided_invoice_id: voided_invoice.id)
      end
    end
  end
end
