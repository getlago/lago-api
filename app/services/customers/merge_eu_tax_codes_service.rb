# frozen_string_literal: true

module Customers
  # Computes the final list of tax codes to apply on a customer once the EU tax
  # automation has resolved a `lago_eu_*` tax code.
  #
  # NOTE: For a non-EU customer without tax identification number, the EU automation
  #       resolves `lago_eu_tax_exempt`. When custom (non `lago_eu_*`) taxes are set on
  #       the customer, they take precedence over the exemption: they are kept, and the
  #       exemption is not added, so the invoice only displays the custom taxes.
  #       In every other case, the EU tax code is added to the given tax codes, or replaces
  #       the customer taxes when no tax codes are given.
  class MergeEuTaxCodesService < BaseService
    Result = BaseResult[:tax_codes]

    EU_TAX_CODE_PREFIX = "lago_eu"
    EU_TAX_EXEMPT_CODE = "lago_eu_tax_exempt"

    def initialize(customer:, eu_tax_code:, tax_codes: nil)
      @customer = customer
      @eu_tax_code = eu_tax_code
      @tax_codes = tax_codes

      super
    end

    def call
      result.tax_codes = if custom_taxes_take_precedence?
        custom_tax_codes
      elsif tax_codes.nil?
        [eu_tax_code]
      else
        (tax_codes + [eu_tax_code]).uniq
      end

      result
    end

    private

    attr_reader :customer, :eu_tax_code, :tax_codes

    def custom_taxes_take_precedence?
      eu_tax_code == EU_TAX_EXEMPT_CODE &&
        customer.tax_identification_number.blank? &&
        custom_tax_codes.any?
    end

    def custom_tax_codes
      @custom_tax_codes ||= (tax_codes.nil? ? customer.taxes.pluck(:code) : tax_codes)
        .reject { |code| code.downcase.start_with?(EU_TAX_CODE_PREFIX) }
        .uniq
    end
  end
end
