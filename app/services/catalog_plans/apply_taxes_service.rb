# frozen_string_literal: true

module CatalogPlans
  class ApplyTaxesService < BaseService
    Result = BaseResult[:applied_taxes]

    def initialize(catalog_plan:, tax_codes:)
      @catalog_plan = catalog_plan
      @tax_codes = tax_codes.uniq
      super
    end

    def call
      return result.not_found_failure!(resource: "plan") unless catalog_plan
      return result.not_found_failure!(resource: "tax") if (tax_codes - taxes_by_code.keys).present?

      catalog_plan.with_lock do
        requested_tax_ids = taxes_by_code.values.map(&:id)

        catalog_plan.applied_taxes.where.not(tax_id: requested_tax_ids).destroy_all

        result.applied_taxes = tax_codes.map do |tax_code|
          catalog_plan.applied_taxes
            .create_with(organization: catalog_plan.organization)
            .find_or_create_by!(tax: taxes_by_code.fetch(tax_code))
        end

        catalog_plan.applied_taxes.reset
        catalog_plan.taxes.reset
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :catalog_plan, :tax_codes

    def taxes_by_code
      @taxes_by_code ||= catalog_plan.organization.taxes.where(code: tax_codes).index_by(&:code)
    end
  end
end
