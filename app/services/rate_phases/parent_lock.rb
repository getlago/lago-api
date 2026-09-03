# frozen_string_literal: true

module RatePhases
  # Shared lock check for the rate-phase services, which all expose a `parent`
  # (a plan or contract rate card). Returns the error code to fail with when
  # the parent is frozen, or nil when it is editable.
  module ParentLock
    private

    def lock_error_code
      case parent
      when PlanRateCard
        "plan_locked" if parent.plan.attached_to_subscriptions?
      when ContractRateCard
        "contract_locked" unless parent.contract.editable?
      end
    end
  end
end
