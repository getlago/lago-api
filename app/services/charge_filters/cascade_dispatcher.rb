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
        # NOTE: group_by yields an array of matching "before" rows. When a predicate has
        #       collapsed onto duplicates there may be several; use the first as the
        #       representative — CascadeService reconciles every matching child row.
        existing = before_by_values.delete(new_filter[:values])&.first

        next if existing &&
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
