# frozen_string_literal: true

module Charges
  class ApplyTaxesService < BaseService
    def initialize(charge:, tax_codes:)
      @charge = charge
      @tax_codes = tax_codes

      super
    end

    def call
      return result.not_found_failure!(resource: 'charge') unless charge
      return result.not_found_failure!(resource: 'tax') if (tax_codes - taxes.pluck(:code)).present?

      result.applied_taxes = tax_codes.map do |tax_code|
        charge.applied_taxes.find_or_create_by!(tax: taxes.find_by(code: tax_code))
      end

      Invoices::RefreshBatchJob.perform_later(charge.plan.invoices.draft.pluck(:id))

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :charge, :tax_codes

    def taxes
      @taxes ||= charge.plan.organization.taxes.where(code: tax_codes)
    end
  end
end
