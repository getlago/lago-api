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

      charge.applied_taxes.where(
        tax_id: charge.taxes.where.not(code: tax_codes).pluck(:id),
      ).destroy_all

      result.applied_taxes = tax_codes.map do |tax_code|
        charge.applied_taxes.find_or_create_by!(tax: taxes.find_by(code: tax_code))
      end

      draft_ids = charge.plan.invoices.draft.pluck(:id)
      Invoices::RefreshBatchJob.perform_later(draft_ids) if draft_ids.present?

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
