# frozen_string_literal: true

module CatalogPlans
  # Soft-deletes a catalog plan. A plan attached to contracts is frozen, so
  # deletion is blocked the same way pricing edits are — its contracts must be
  # migrated first. Otherwise its plan rate cards (and their phases and
  # overrides) are torn down alongside it.
  class DestroyService < BaseService
    Result = BaseResult[:catalog_plan]

    def initialize(catalog_plan:)
      @catalog_plan = catalog_plan
      super
    end

    activity_loggable(
      action: "plan.deleted",
      record: -> { catalog_plan }
    )

    def call
      return result.not_found_failure!(resource: "plan") unless catalog_plan

      if catalog_plan.attached_to_contracts?
        return result.single_validation_failure!(field: :plan, error_code: "plan_locked")
      end

      ActiveRecord::Base.transaction do
        catalog_plan.applied_rate_cards.to_a.each do |plan_rate_card|
          PlanRateCards::DestroyService.call!(plan_rate_card:)
        end
        catalog_plan.discard!
      end

      result.catalog_plan = catalog_plan
      SendWebhookJob.perform_after_commit("plan.deleted", catalog_plan)
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue BaseService::FailedResult => e
      e.result
    end

    private

    attr_reader :catalog_plan
  end
end
