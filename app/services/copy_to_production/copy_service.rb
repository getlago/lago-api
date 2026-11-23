# frozen_string_literal: true

module CopyToProduction
  class CopyService < BaseService
    Result = BaseResult[:item, :copied_items, :reused_items]

    def call
      previous_membership = CurrentContext.membership
      check_entry
      return result if result.failure?

      ActiveRecord::Base.transaction do
        # Membership and activation writes lock production too, so the checks below read their committed state.
        Organizations::SandboxLockService.call!(organization: production)

        plan = build_plan
        reason = blocking_reason(plan)

        if reason
          refuse(reason)
        else
          # Attributes the activity logs and the tracking of the create services to the user's production membership.
          CurrentContext.membership = "membership/#{production_membership.id}"
          copy(plan)
        end
      end

      result
    rescue BaseService::FailedResult => e
      result.fail_with_error!(e.result.error)
    rescue ActiveRecord::RecordNotUnique => e
      unique_index_failure!(e, item.unique_indexes)
    ensure
      # After the commit, which runs the activity logs.
      CurrentContext.membership = previous_membership
    end

    private

    def refuse(reason)
      if reason == "value_already_exist"
        result.single_validation_failure!(field: :code, error_code: reason)
      else
        result.forbidden_failure!(code: reason)
      end
    end

    # A create service that refuses raises, so nothing is copied unless everything is.
    def copy(plan)
      resolved = plan.reused.to_h { [it.key, it.existing] }

      plan.copied.each do |step|
        record = step.item.copy!(step.source, resolved)
        resolved[step.key] = record
        Utils::ActivityLog.produce_after_commit(record, step.item.activity_type)
      end

      result.item = plan.copied.last.entry(resolved.fetch(plan.copied.last.key))
      result.copied_items = plan.copied.map { it.entry(resolved.fetch(it.key)) }
      result.reused_items = plan.reused.map { it.entry(it.existing) }
    end
  end
end
