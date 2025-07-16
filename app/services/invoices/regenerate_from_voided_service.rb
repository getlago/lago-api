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
        process_fees(invoice)
        create_invoice_subscription(invoice) if invoice.invoice_type == "subscription"
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

    def process_fees(invoice)
      fees_params.each do |fee_params|
        if !fee_params[:id].blank?
          voided_fee = voided_invoice.fees.find_by(id: fee_params[:id])
          duplicate_fee(voided_fee, fee_params, invoice) if voided_fee
        else
          pp "fazer esta parte"
          ##create_new_fee(fee, invoice)
        end
      end
    end

    def duplicate_fee(voided_fee, fee_params, invoice)
      unit_precise_amount_cents = fee_params[:unit_amount_cents].to_f || voided_fee.unit_amount_cents
      unit_precise_amount_cents = unit_precise_amount_cents * voided_fee.amount.currency.subunit_to_unit
      units = fee_params[:units]&.to_f || voided_fee.units


      voided_fee.dup.tap do |dup_fee|
        dup_fee.invoice = invoice
        dup_fee.payment_status = :pending
        dup_fee.taxes_amount_cents = 0
        dup_fee.taxes_precise_amount_cents = 0.to_d

        dup_fee.invoice_display_name = fee_params[:invoice_display_name] if fee_params[:invoice_display_name].present?
        dup_fee.units = units
        dup_fee.amount_cents =  (unit_precise_amount_cents * units).round
        dup_fee.precise_amount_cents = unit_precise_amount_cents * units
        dup_fee.unit_amount_cents = fee_params[:unit_amount_cents] if fee_params[:unit_amount_cents].present?
        dup_fee.precise_unit_amount = fee_params[:unit_amount_cents] if fee_params[:unit_amount_cents].present?

        dup_fee.save!
      end
    end
  end
end
