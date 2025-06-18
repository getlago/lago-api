# frozen_string_literal: true

module Invoices
  class RegenerateService < BaseService
    def initialize(invoice:, fees: nil)
      @invoice = invoice
      @fees = fees
      super
    end

    activity_loggable(
      action: "invoice.regenerated",
      record: -> { invoice }
    )

    def call
      return result.not_found_failure!(resource: "invoice") unless invoice
      return result.not_allowed_failure!(code: "not_voided") unless invoice.voided?
      return result.not_found_failure!(resource: "fees") if fees.blank?

      ActiveRecord::Base.transaction do
        generating_result = Invoices::CreateGeneratingService.call(
          customer: invoice.customer,
          invoice_type: invoice.invoice_type,
          currency: invoice.currency,
          datetime: Time.current
        )
        generating_result.raise_if_error!

        new_invoice = generating_result.invoice

        # TODO: add field void_invoice_id to reference original invoice
        # new_invoice.void_invoice_id = invoice.id if new_invoice.respond_to?(:void_invoice_id=)

        created_fees = []
        fees.each do |fee_params|
          unit_amount_cents = fee_params[:unit_amount_cents]
          units = fee_params[:units]&.to_f || 1
          tax_codes = fee_params[:tax_codes]

          new_fee = Fee.new(
            invoice: new_invoice,
            organization_id: new_invoice.organization_id,
            billing_entity_id: new_invoice.billing_entity_id,
            invoice_display_name: fee_params[:invoice_display_name],
            description: fee_params[:description],
            unit_amount_cents: unit_amount_cents,
            amount_cents: (unit_amount_cents * units).round,
            precise_amount_cents: unit_amount_cents * units.to_d,
            amount_currency: new_invoice.currency,
            fee_type: :add_on,
            units: units,
            payment_status: :pending,
            taxes_amount_cents: 0,
            taxes_precise_amount_cents: 0.to_d
          )

          taxes_result = tax_codes.present? ?
            Fees::ApplyTaxesService.call(fee: new_fee, tax_codes: tax_codes) :
            Fees::ApplyTaxesService.call(fee: new_fee)

          taxes_result.raise_if_error!

          new_fee.save!
          created_fees << new_fee
        end

        Invoices::ComputeAmountsFromFees.call(invoice: new_invoice)

        new_invoice.status = :draft
        new_invoice.save!

        result.invoice = new_invoice
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue BaseService::FailedResult => e
      e.result
    rescue => e
      result.fail_with_error!(e)
    end

    private

    attr_reader :invoice, :fees
  end
end
