# frozen_string_literal: true

module CatalogWallets
  class ApplyTaxesService < BaseService
    Result = BaseResult[:applied_taxes]

    def initialize(wallet:, tax_codes:)
      @wallet = wallet
      @tax_codes = tax_codes.uniq
      super
    end

    def call
      return result.not_found_failure!(resource: "wallet") unless wallet
      return result.not_found_failure!(resource: "tax") if (tax_codes - taxes_by_code.keys).present?

      wallet.with_lock do
        requested_tax_ids = taxes_by_code.values.map(&:id)

        wallet.applied_taxes.where.not(tax_id: requested_tax_ids).destroy_all

        result.applied_taxes = tax_codes.map do |tax_code|
          wallet.applied_taxes
            .create_with(organization: wallet.organization)
            .find_or_create_by!(tax: taxes_by_code.fetch(tax_code))
        end

        wallet.applied_taxes.reset
        wallet.taxes.reset
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :wallet, :tax_codes

    def taxes_by_code
      @taxes_by_code ||= wallet.organization.taxes.where(code: tax_codes).index_by(&:code)
    end
  end
end
