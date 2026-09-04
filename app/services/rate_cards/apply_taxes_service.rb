# frozen_string_literal: true

module RateCards
  class ApplyTaxesService < BaseService
    Result = BaseResult[:applied_taxes]

    def initialize(rate_card:, tax_codes:)
      @rate_card = rate_card
      @tax_codes = tax_codes.uniq
      super
    end

    def call
      return result.not_found_failure!(resource: "rate_card") unless rate_card
      return result.not_found_failure!(resource: "tax") if (tax_codes - taxes_by_code.keys).present?

      rate_card.with_lock do
        rate_card.applied_taxes.where.not(tax_id: taxes_by_code.values.map(&:id)).destroy_all

        result.applied_taxes = tax_codes.map do |tax_code|
          rate_card.applied_taxes
            .create_with(organization: rate_card.organization)
            .find_or_create_by!(tax: taxes_by_code.fetch(tax_code))
        end

        rate_card.applied_taxes.reset
        rate_card.taxes.reset
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :rate_card, :tax_codes

    def taxes_by_code
      @taxes_by_code ||= rate_card.organization.taxes.where(code: tax_codes).index_by(&:code)
    end
  end
end
