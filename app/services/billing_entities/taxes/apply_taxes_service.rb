# frozen_string_literal: true

module BillingEntities
  module Taxes
    class ApplyTaxesService < BaseService
      Result = BaseResult[:applied_taxes, :taxes]

      def initialize(billing_entity:, tax_codes:)
        @billing_entity = billing_entity
        @tax_codes = tax_codes

        super
      end

      def call
        result.applied_taxes = []

        find_taxes_on_organization
        return result if result.failure?

        result.applied_taxes = result.taxes.map do |tax|
          billing_entity.applied_taxes.find_or_create_by!(tax:)
        end

        result
      end

      private

      attr_reader :billing_entity, :tax_codes

      delegate :organization, to: :billing_entity

      def find_taxes_on_organization
        result.taxes = organization.taxes.where(code: tax_codes)

        if result.taxes.count != tax_codes.count
          result.not_found_failure!(resource: "tax")
        end
      end
    end
  end
end
