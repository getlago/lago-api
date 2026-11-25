# frozen_string_literal: true

module CopyToProduction
  # What CopyToProduction::CopyService would do: the sandbox items it would copy, the production items it would reuse, and
  # the reason it would refuse the copy, if any. The copy runs as the copy's, without the lock, and is rolled back.
  class PreviewService < BaseService
    Result = BaseResult[
      :copied_items, :reused_items, :blocking_reason, :missing_parent, :refused_item, :refusal_code, :refusal_field
    ]

    def call
      check_entry
      return result if result.failure?

      # A user who cannot move to production does not see what it holds.
      reason = access_refusal
      if reason
        result.copied_items = []
        result.reused_items = []
        result.blocking_reason = reason
        return result
      end

      plan = build_plan
      result.copied_items = plan.copied.map(&:entry)
      result.reused_items = plan.reused.map { it.entry(it.existing) }
      result.missing_parent = plan.missing_parent&.entry

      reason, refused_step = plan_refusal(plan)
      if reason
        result.blocking_reason = reason
        result.refused_item = refused_step&.entry
      else
        dry_run(plan)
      end

      result
    end

    private

    # A new savepoint, so that the rollback holds inside a caller's transaction too.
    def dry_run(plan)
      copied = 0

      ActiveRecord::Base.transaction(requires_new: true) do
        copy(plan) { copied += 1 }
        raise ActiveRecord::Rollback
      end
    rescue BaseService::FailedResult => e
      result.blocking_reason = "copy_to_production_item_refused"
      result.refused_item = plan.copied[copied].entry
      result.refusal_code, result.refusal_field = refusal_of(e.result.error)
    end

    # The code and field the copy's GraphQL error would answer: the first validation error, or the resource not found.
    def refusal_of(error)
      case error
      when BaseService::ValidationFailure
        field, codes = error.messages.first
        codes = codes.is_a?(Hash) ? codes.values.first : codes.first while codes.is_a?(Hash) || codes.is_a?(Array)
        [codes.to_s, field.to_s]
      when BaseService::NotFoundFailure
        ["not_found", error.resource.to_s]
      else
        [error.try(:code) || error.message, nil]
      end
    end
  end
end
