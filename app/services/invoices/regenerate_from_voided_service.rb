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
        adjust_feea(invoice)
        Invoices::ApplyInvoiceCustomSectionsService.call(invoice: invoice)
        Invoices::ComputeAmountsFromFees.call(invoice: invoice)
        Invoices::TransitionToFinalStatusService.call(invoice: invoice)
        invoice.save!
      end

      result.invoice = invoice
      result
    end

    private

    attr_reader :voided_invoice, :fees_params

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

    def adjust_feea(invoice)
      invoice.fees.each do |fee|
        adjusted_fee = fee.adjusted_fee
        fee.invoice_display_name = fee.adjusted_fee.invoice_display_name if adjusted_fee.invoice_display_name.present?
        byebug
        fee.charge_id = adjusted_fee.charge_id if adjusted_fee.charge_id.present?
        fee.subscription_id = adjusted_fee.subscription_id if adjusted_fee.subscription_id.present?

        fee.units = adjusted_fee.units if adjusted_fee.units.present?


        units = fee.units
        subunit = invoice.total_amount.currency.subunit_to_unit
        unit_precise_amount_cents = adjusted_fee.unit_precise_amount_cents
        fee.unit_amount_cents = unit_precise_amount_cents.round
        fee.precise_unit_amount = unit_precise_amount_cents.to_d / subunit
        fee.amount_cents = (units * unit_precise_amount_cents).round
        fee.precise_amount_cents = units * unit_precise_amount_cents
        fee.save!
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
          unit_precise_amount: fee_params[:unit_amount_cents],
          charge_id: fee_params[:charge_id],
          subscription_id: fee_params[:subscription_id]
        }

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
      dup_fee.taxes_precise_amount_cents = 0.to_d
      dup_fee.save!
      dup_fee
    end
  end
end
