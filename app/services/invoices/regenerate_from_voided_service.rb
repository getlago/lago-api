module Invoices
  class RegenerateFromVoidedService < BaseService
    def initialize(voided_invoice:, fees: nil)
      @voided_invoice = voided_invoice
      @fees = fees
      super
    end

    activity_loggable(
      action: "invoice.regenerated_from_voided",
      record: -> { voided_invoice }
    )

    def call
      return result.not_found_failure!(resource: "invoice") unless voided_invoice
      return result.not_allowed_failure!(code: "not_voided") unless voided_invoice.voided?
      return result.not_found_failure!(resource: "fees") if fees.blank?

      ActiveRecord::Base.transaction do
        generating_result = Invoices::CreateGeneratingService.call(
          void_invoice_id: voided_invoice.id,
          customer: voided_invoice.customer,
          invoice_type: voided_invoice.invoice_type,
          currency: voided_invoice.currency,
          datetime: Time.current
        )
        generating_result.raise_if_error!

        new_invoice = generating_result.invoice

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

    attr_reader :voided_invoice, :fees
  end
end
