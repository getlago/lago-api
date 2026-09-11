# frozen_string_literal: true

module Fees
  class ApplyProviderTaxesService < BaseService
    Result = BaseResult[:applied_taxes]

    def initialize(fee:, fee_taxes:)
      @fee = fee
      @fee_taxes = fee_taxes

      super
    end

    def call
      result.applied_taxes = []
      return result if fee.applied_taxes.any?
      return result if fee_taxes.nil? && !fee.taxable?
      return unreported_fee_failure if fee_taxes.nil?

      applied_taxes_amount_cents = 0
      applied_precise_taxes_amount_cents = 0.to_d
      applied_taxes_rate = 0
      taxes_base_rate = taxes_base_rate(fee_taxes.tax_breakdown.first)

      fee_taxes.tax_breakdown.each do |tax|
        tax_rate = tax.rate.to_f * 100

        applied_tax = Fee::AppliedTax.new(
          organization_id: fee.organization_id,
          tax_description: tax.type,
          tax_code: tax.name.parameterize(separator: "_"),
          tax_name: tax.name,
          tax_rate: tax_rate,
          amount_currency: fee.amount_currency
        )
        fee.applied_taxes << applied_tax

        # NOTE: A charge priced as one line item by the provider comes back with an amount already
        #       allocated across its fees so the group total stays exact; recomputing it from this
        #       fee's sub-total would round it a second time.
        tax_amount_cents = tax.allocated_amount_cents ||
          (fee.sub_total_excluding_taxes_amount_cents * taxes_base_rate * tax_rate).fdiv(100)
        tax_precise_amount_cents = (fee.sub_total_excluding_taxes_precise_amount_cents * taxes_base_rate * tax_rate).fdiv(100.to_d)

        applied_tax.amount_cents = tax_amount_cents.round
        applied_tax.precise_amount_cents = tax_precise_amount_cents
        applied_tax.save! if fee.persisted?

        applied_taxes_amount_cents += tax_amount_cents
        applied_precise_taxes_amount_cents += tax_precise_amount_cents
        applied_taxes_rate += tax_rate

        result.applied_taxes << applied_tax
      end

      fee.taxes_amount_cents = applied_taxes_amount_cents.round
      fee.taxes_precise_amount_cents = applied_precise_taxes_amount_cents
      fee.taxes_rate = applied_taxes_rate
      fee.taxes_base_rate = taxes_base_rate

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :fee, :fee_taxes

    # NOTE: A fee with no amount is left out of the provider request, so having no entry in the
    #       response is expected. Any other fee missing from a successful response means the
    #       response is incomplete, and taxing it as zero would under-charge it silently.
    def unreported_fee_failure
      result.service_failure!(
        code: "fee_missing_from_tax_response",
        message: "Fee #{fee.id} is missing from the provider tax response"
      )
    end

    def taxes_base_rate(tax)
      return 1 unless tax

      tax_rate = tax.rate.to_f * 100
      tax_amount_cents = (fee.sub_total_excluding_taxes_amount_cents * tax_rate).fdiv(100)

      if tax.tax_amount < tax_amount_cents
        tax.tax_amount.fdiv(tax_amount_cents)
      else
        1
      end
    end
  end
end
