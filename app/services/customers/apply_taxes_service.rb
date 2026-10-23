# frozen_string_literal: true

module Customers
  class ApplyTaxesService < BaseService
    include Customers::Concerns::EuExemptionOverride

    Result = BaseResult[:applied_taxes]

    def initialize(customer:, tax_codes:)
      @customer = customer
      @requested_tax_codes = tax_codes

      super
    end

    def call
      return result.not_found_failure!(resource: "customer") unless customer
      return result.not_found_failure!(resource: "tax") if (tax_codes - taxes.pluck(:code)).present?

      customer.applied_taxes.where(
        tax_id: customer.taxes.where.not(code: tax_codes).pluck(:id)
      ).destroy_all

      result.applied_taxes = tax_codes.map do |tax_code|
        customer.applied_taxes
          .create_with(organization_id: customer.organization_id)
          .find_or_create_by!(tax: taxes.find_by(code: tax_code))
      end

      customer.invoices.draft.update_all(ready_to_be_refreshed: true) # rubocop:disable Rails/SkipsModelValidations

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :customer, :requested_tax_codes

    # Custom taxes replace the EU exemption on these customers, which fall back to it when none is left.
    def tax_codes
      @tax_codes ||= if !eu_exemption_overridable?
        requested_tax_codes
      elsif requested_tax_codes.any? { |code| custom_tax_code?(code) }
        requested_tax_codes - [EU_TAX_EXEMPT_CODE]
      elsif requested_tax_codes.empty? && customer.organization.taxes.exists?(code: EU_TAX_EXEMPT_CODE)
        [EU_TAX_EXEMPT_CODE]
      else
        requested_tax_codes
      end
    end

    def taxes
      @taxes ||= customer.organization.taxes.where(code: tax_codes)
    end
  end
end
