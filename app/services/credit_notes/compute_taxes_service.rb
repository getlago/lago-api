# frozen_string_literal: true

module CreditNotes
  class ComputeTaxesService < BaseService
    Result = BaseResult[:credit_note, :coupons_adjustment_amount_cents]

    def initialize(credit_note:, adjust_rounding: false)
      @credit_note = credit_note
      @adjust_rounding = adjust_rounding

      super()
    end

    def call
      taxes_result = ApplyTaxesService.call(invoice: credit_note.invoice, items: credit_note.items)
      return result.fail_with_error!(taxes_result.error) unless taxes_result.success?

      credit_note.precise_coupons_adjustment_amount_cents = taxes_result.coupons_adjustment_amount_cents
      credit_note.coupons_adjustment_amount_cents = taxes_result.coupons_adjustment_amount_cents.round
      credit_note.precise_taxes_amount_cents = taxes_result.precise_taxes_amount_cents
      if adjust_rounding
        credit_note.precise_taxes_amount_cents -= credit_note.invoice.credit_notes.sum(&:taxes_rounding_adjustment)
      end
      credit_note.taxes_amount_cents = credit_note.precise_taxes_amount_cents.round
      credit_note.taxes_rate = taxes_result.taxes_rate

      if credit_note.invoice.provider_taxes?
        amounts = Integrations::Aggregator::Taxes::Allocation.call(credit_note.taxes_amount_cents, taxes_result.precise_tax_amounts)
        taxes_result.applied_taxes.each_with_index { |tax, index| tax.amount_cents = amounts[index] }
      end
      taxes_result.applied_taxes.each { |applied_tax| credit_note.applied_taxes << applied_tax }

      result.credit_note = credit_note
      result.coupons_adjustment_amount_cents = taxes_result.coupons_adjustment_amount_cents
      result
    end

    private

    attr_reader :credit_note, :adjust_rounding
  end
end
