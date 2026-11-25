# frozen_string_literal: true

module CopyToProduction
  class CopyService < BaseService
    Result = BaseResult[:item]

    def call
      check_entry
      return result if result.failure?

      # The create services log and track after the commit, attributed to the user's production membership.
      CurrentContext.set(membership: production_membership&.then { "membership/#{it.id}" }) do
        ActiveRecord::Base.transaction do
          # Membership and activation writes lock production too, so the checks below read their committed state.
          Organizations::SandboxLockService.call!(organization: production)

          reason = access_refusal
          plan = build_plan unless reason
          reason ||= plan_refusal(plan)&.first

          reason ? refuse(reason) : move(plan)
        end
      end

      result
    rescue BaseService::FailedResult => e
      result.fail_with_error!(e.result.error)
    end

    private

    def refuse(reason)
      if reason == "value_already_exist"
        result.single_validation_failure!(field: :code, error_code: reason)
      else
        result.forbidden_failure!(code: reason)
      end
    end

    def copy(plan)
      copy(plan) do |step, record|
        Utils::ActivityLog.produce_after_commit(record, step.item.activity_type)
        result.item = step.entry(record) if step.key == plan.requested.key
      end
    end
  end
end
