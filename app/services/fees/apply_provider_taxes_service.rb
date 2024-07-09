# frozen_string_literal: true

module Fees
  class ApplyProviderTaxesService < BaseService
    def initialize(fee:, fee_taxes:)
      @fee = fee
      @fee_taxes = fee_taxes

      super
    end

    def call
      result.applied_taxes = []
      return result if fee.applied_taxes.any?

      applied_taxes_amount_cents = 0
      applied_taxes_rate = 0

      fee_taxes.tax_breakdown.each do |tax|
        tax_rate = tax.rate.to_f * 100

        applied_tax = Fee::AppliedTax.new(
          tax_description: tax.type,
          tax_code: tax.name.parameterize(separator: '_'),
          tax_name: tax.name,
          tax_rate: tax_rate,
          amount_currency: fee.amount_currency
        )
        fee.applied_taxes << applied_tax

        tax_amount_cents = tax.tax_amount
        applied_tax.amount_cents = tax_amount_cents.round
        applied_tax.save! if fee.persisted?

        applied_taxes_amount_cents += tax_amount_cents
        applied_taxes_rate += tax_rate

        result.applied_taxes << applied_tax
      end

      fee.taxes_amount_cents = applied_taxes_amount_cents.round
      fee.taxes_rate = applied_taxes_rate

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :fee, :fee_taxes
  end
end
