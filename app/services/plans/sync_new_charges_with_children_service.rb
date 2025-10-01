# frozen_string_literal: true

module Plans
  class SyncNewChargesWithChildrenService < BaseService
    Result = BaseResult
    def initialize(plan:)
      @plan = plan
      super
    end

    def call
      # Note: this check is only needed if child charges "lost" their parents:
      # when a parent plan was updated without sending charges_ids, so the "original" parents were deleted
      return result.forbidden_failure!(code: "plan_has_undistinguishable_charges") if plan_has_undistinguishable_charges?

      plan.charges.each do |charge|
        sync_charge_for_children(charge)
      end
    end

    private

    attr_reader :plan

    def sync_charge_for_children(charge)
      plan.children.joins(:subscriptions).where(subscriptions: {status: %w[active pending]}).distinct.pluck(:id).each_slice(20) do |child_ids|
        Charges::SyncChildrenBatchJob.perform_later(
          children_plans_ids: child_ids,
          charge:
        )
      end
    end

    def plan_has_undistinguishable_charges?
      # we can also add a check by filters as well
      all_charges_summary = plan.charges.map { |ch| {metric: ch.billable_metric_id, charge_model: ch.charge_model} }
      all_charges_summary.uniq.count != all_charges_summary.count
    end
  end
end
