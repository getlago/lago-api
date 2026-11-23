# frozen_string_literal: true

module CopyToProduction
  # What CopyToProduction::CopyService would do, without a lock or a write: the sandbox items it would copy, the production
  # items it would reuse, and the reason it would refuse the copy, if any.
  class PreviewService < BaseService
    Result = BaseResult[:copied_items, :reused_items, :blocking_reason, :missing_parent]

    def call
      check_entry
      return result if result.failure?

      plan = build_plan

      result.copied_items = plan.copied.map(&:entry)
      result.reused_items = plan.reused.map { it.entry(it.existing) }
      result.blocking_reason = blocking_reason(plan)
      result.missing_parent = plan.missing_parent&.entry
      result
    end
  end
end
