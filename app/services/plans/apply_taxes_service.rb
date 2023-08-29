# frozen_string_literal: true

module Plans
  class ApplyTaxesService < BaseService
    def initialize(plan:, tax_codes:)
      @plan = plan
      @tax_codes = tax_codes

      super
    end

    def call
      return result.not_found_failure!(resource: 'plan') unless plan
      return result.not_found_failure!(resource: 'tax') if (tax_codes - taxes.pluck(:code)).present?

      plan.applied_taxes.where(
        tax_id: plan.taxes.where.not(code: tax_codes).pluck(:id),
      ).destroy_all

      result.applied_taxes = tax_codes.map do |tax_code|
        plan.applied_taxes.find_or_create_by!(tax: taxes.find_by(code: tax_code))
      end

      draft_ids = plan.invoices.draft.pluck(:id)
      Invoices::RefreshBatchJob.perform_later(draft_ids) if draft_ids.present?

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :plan, :tax_codes

    def taxes
      @taxes ||= plan.organization.taxes.where(code: tax_codes)
    end
  end
end
