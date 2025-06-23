# frozen_string_literal: true

module Invoices
  class RegenerateFromVoidedService < BaseService
    def initialize(voided_invoice:, fees:)
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

      fee_records = Fee.where(id: fees, organization: voided_invoice.organization)
      return result.not_found_failure!(resource: "fees") if fee_records.count != fees.count

      ActiveRecord::Base.transaction do
        generating_result = Invoices::CreateGeneratingService.call(
          voided_invoice_id: voided_invoice.id,
          customer: voided_invoice.customer,
          invoice_type: voided_invoice.invoice_type,
          currency: voided_invoice.currency,
          datetime: Time.current
        )
        generating_result.raise_if_error!

        new_invoice = generating_result.invoice

        fee_records.each do |fee_record|
          new_fee = fee_record.dup.tap do |fee|
            fee.invoice = new_invoice
            fee.organization_id = new_invoice.organization_id
            fee.billing_entity_id = new_invoice.billing_entity_id
            fee.amount_currency = new_invoice.currency
            fee.payment_status = :pending
            fee.taxes_amount_cents = 0
            fee.taxes_precise_amount_cents = 0.to_d
          end

          taxes_result = Fees::ApplyTaxesService.call(fee: new_fee)

          taxes_result.raise_if_error!

          new_fee.save!
        end

        Invoices::ComputeAmountsFromFees.call(invoice: new_invoice)

        new_invoice.draft!

        result.invoice = new_invoice
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue BaseService::FailedResult => e
      e.result
    rescue => e
      result.fail_with_error!(e, code: "unexpected_error")
    end

    private

    attr_reader :voided_invoice, :fees
  end
end
