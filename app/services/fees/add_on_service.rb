# frozen_string_literal: true

module Fees
  class AddOnService < BaseService
    Result = BaseResult[:fee]

    def initialize(invoice:, applied_add_on:)
      @invoice = invoice
      @applied_add_on = applied_add_on
      super(nil)
    end

    def create
      return result if already_billed?

      amount_cents = applied_add_on.amount_cents

      new_fee = Fee.new(
        invoice:,
        organization_id: invoice.organization_id,
        billing_entity_id: invoice.billing_entity_id,
        applied_add_on:,
        amount_cents:,
        precise_amount_cents: amount_cents.to_d,
        amount_currency: applied_add_on.amount_currency,
        fee_type: :add_on,
        invoiceable_type: "AppliedAddOn",
        invoiceable: applied_add_on,
        units: 1,
        payment_status: :pending,
        taxes_amount_cents: 0,
        taxes_precise_amount_cents: 0.to_d
      )

      taxes_result = Fees::ApplyTaxesService.call(fee: new_fee)
      taxes_result.raise_if_error!

      new_fee.save!

      result.fee = new_fee

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :invoice, :applied_add_on

    def already_billed?
      existing_fee = invoice.fees.find_by(applied_add_on_id: applied_add_on.id)
      return false unless existing_fee

      result.fee = existing_fee
      true
    end
  end
end
