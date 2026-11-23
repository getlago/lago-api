# frozen_string_literal: true

module CopyToProduction
  class CopyService < BaseService
    Result = BaseResult[:item, :copied_items, :reused_items]

    def call
      check_entry
      return result if result.failure?

      # A savepoint, so that a failure rolls the copies back inside a caller's transaction too.
      ActiveRecord::Base.transaction(requires_new: true) do
        # Membership and activation writes lock production too, so the checks below read their committed state.
        Organizations::SandboxLockService.call!(organization: production)

        reason = access_refusal
        plan = build_plan unless reason
        reason ||= plan_refusal(plan)

        if reason
          refuse(reason)
        else
          attribute_to_production_membership { move(plan) }
        end
      end

      result
    rescue BaseService::FailedResult => e
      result.fail_with_error!(e.result.error)
    rescue ActiveRecord::RecordNotUnique => e
      unique_index_failure!(e, item.unique_indexes)
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
        log_move(record, step.item.activity_type)
      end

      result.item = plan.copied.last.entry(resolved.fetch(plan.copied.last.key))
      result.copied_items = plan.copied.map { it.entry(resolved.fetch(it.key)) }
      result.reused_items = plan.reused.map { it.entry(it.existing) }
    end

    # Reads the membership when the log runs, after the commit of the outermost transaction.
    def log_move(record, activity_type)
      membership = production_membership_context

      after_commit do
        CurrentContext.set(membership:) { Utils::ActivityLog.produce(record, activity_type) }
      end
    end

    # Attributes what the create services log and track to the user's production membership. They read it after the
    # commit of the outermost transaction, so it is restored once they have run, or on a rollback.
    def attribute_to_production_membership
      previous_membership = CurrentContext.membership
      restore = -> { CurrentContext.membership = previous_membership }
      after_rollback(&restore)

      CurrentContext.membership = production_membership_context
      yield
      after_commit(&restore)
    end

    def production_membership_context
      "membership/#{production_membership.id}"
    end
  end
end
