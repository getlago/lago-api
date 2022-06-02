# frozen_string_literal: true

module Fees
  class AddOnService < BaseService
    def initialize(invoice:, applied_add_on:)
      @invoice = invoice
      @applied_add_on = applied_add_on
      super(nil)
    end

    def create
      return result if already_billed?

      new_fee = Fee.new(
        invoice: invoice,
        subscription: subscription,
        applied_add_on: applied_add_on,
        amount_cents: applied_add_on.amount_cents,
        amount_currency: plan.amount_currency,
        vat_rate: customer.applicable_vat_rate,
        units: 1,
      )

      new_fee.compute_vat
      new_fee.save!

      result.fee = new_fee
      result
    rescue ActiveRecord::RecordInvalid => e
      result.fail_with_validations!(e.record)
    end

    private

    attr_reader :invoice, :applied_add_on

    delegate :customer, :plan, :subscription, to: :invoice

    def already_billed?
      existing_fee = invoice.fees.find_by(applied_add_on_id: applied_add_on.id)
      return false unless existing_fee

      result.fee = existing_fee
      true
    end
  end
end
