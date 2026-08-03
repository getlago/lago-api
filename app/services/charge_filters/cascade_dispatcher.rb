# frozen_string_literal: true

module ChargeFilters
  module CascadeDispatcher
    module_function

    # Diffs `before` against `after` and enqueues one ChargeFilters::CascadeJob
    # per change. `before` and `after` are arrays of:
    #   { values: {"key" => [...]}, properties: {...} | nil, invoice_display_name: "..." }
    # `values` and `properties` must be string-keyed.
    def call(charge:, before:, after:)
      before_by_values = before.group_by { |f| f[:values] }

      after.each do |new_filter|
        # NOTE: group_by yields every "before" row sharing this predicate. A metric edit can
        #       collapse several filters onto one predicate, so the group may hold duplicates.
        existing_group = before_by_values.delete(new_filter[:values]) || []
        existing = existing_group.first

        # NOTE: only treat this as a no-op when the predicate resolved to a single row that
        #       is unchanged. If the group carries duplicates, the parent has just been
        #       deduplicated to one row and the children still hold the extras, so a job must
        #       be enqueued for CascadeService to reconcile that cardinality.
        next if existing_group.size == 1 &&
          existing[:properties] == new_filter[:properties] &&
          existing[:invoice_display_name] == new_filter[:invoice_display_name]

        ChargeFilters::CascadeJob.perform_later(
          charge.id,
          existing ? "update" : "create",
          new_filter[:values],
          existing&.dig(:properties),
          new_filter[:properties],
          new_filter[:invoice_display_name]
        )
      end

      before_by_values.each_value do |old_group|
        old = old_group.first
        ChargeFilters::CascadeJob.perform_later(
          charge.id,
          "destroy",
          old[:values],
          old[:properties],
          nil,
          old[:invoice_display_name]
        )
      end
    end
  end
end
