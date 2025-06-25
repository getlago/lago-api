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

      existing_fees = voided_invoice.fees.where(id: fees.map { |fee| fee[:id] })
      new_fees = fees.select { |fee| fee[:id].blank? }

      ActiveRecord::Base.transaction do
        generating_result = Invoices::CreateGeneratingService.call(
          voided_invoice_id: voided_invoice.id,
          customer: voided_invoice.customer,
          invoice_type: voided_invoice.invoice_type,
          currency: voided_invoice.currency,
          datetime: Time.current
        ) do |invoice|
          existing_fees.each do |fee_record|
            fee_record.dup.tap do |fee|
              fee.invoice = invoice
              fee.payment_status = :pending
              fee.taxes_amount_cents = 0
              fee.taxes_precise_amount_cents = 0.to_d

              fee.save!

              taxes_result = Fees::ApplyTaxesService.call(fee: fee)
              taxes_result.raise_if_error!
            end
          end

          new_fees.each do |fee_attributes|
            new_fee = Fee.create!(fee_attributes.merge(invoice: invoice))

            taxes_result = Fees::ApplyTaxesService.call(fee: new_fee)
            taxes_result.raise_if_error!

            new_fee.save!
          end

          amounts_from_fees_result = Invoices::ComputeAmountsFromFees.call(invoice: invoice)
          amounts_from_fees_result.raise_if_error!

          invoice.draft!
        end

        # INVESTIGATE: Since The CreateGeneratingService has it own transaction block we need to handle orphan invoice here in case of error.
        generating_result.raise_if_error!

        result.invoice = generating_result.invoice
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue BaseService::FailedResult => e
      e.result
    end

    private

    attr_reader :voided_invoice, :fees
  end
end
