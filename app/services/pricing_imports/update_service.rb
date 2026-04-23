# frozen_string_literal: true

module PricingImports
  class UpdateService < BaseService
    Result = BaseResult[:pricing_import]

    def initialize(pricing_import:, edited_plan:)
      @pricing_import = pricing_import
      @edited_plan = edited_plan || {}
      super
    end

    def call
      unless pricing_import.draft?
        return result.validation_failure!(errors: {state: ["cannot_edit_after_confirmation"]})
      end

      pricing_import.update!(
        edited_plan: edited_plan,
        progress_total: compute_total(edited_plan)
      )

      result.pricing_import = pricing_import
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :pricing_import, :edited_plan

    def compute_total(plan)
      bm = (plan["billable_metrics"] || []).size
      pl = (plan["plans"] || []).size
      bm + pl
    end
  end
end
