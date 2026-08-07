# frozen_string_literal: true

module ChargeFilters
  module CascadeDispatcher
    module_function

    # Diffs `before` against `after` and enqueues one ChargeFilters::CascadeJob
    # per change. `before` and `after` are arrays of:
    #   { values: {"key" => [...]}, properties: {...} | nil, invoice_display_name: "..." }
    # `values` and `properties` must be string-keyed.
    #
    # `values` is the filter's predicate, and it is what a job targets. Filters left on
    # the same predicate by an older billable metric change are cascaded as one group.
    def call(charge:, before:, after:)
      before_by_predicate = before.group_by { |filter| filter[:values] }

      after.each do |new_filter|
        previous_filters = before_by_predicate.delete(new_filter[:values]) || []
        previous = previous_filters.first

        # Several filters on one predicate still need a job, even when the kept one is
        # unchanged: the cascade is what discards the duplicates on the override
        next if previous_filters.one? && unchanged?(previous, new_filter)

        enqueue(
          charge,
          previous ? "update" : "create",
          new_filter[:values],
          previous&.dig(:properties),
          new_filter[:properties],
          new_filter[:invoice_display_name]
        )
      end

      # Predicates no filter in `after` claimed are the removed ones. A job targets a
      # predicate and the cascade discards every child filter on it, so one job covers
      # the group and any of its filters can carry the payload.
      before_by_predicate.each_value do |removed_filters|
        removed = removed_filters.first

        enqueue(
          charge,
          "destroy",
          removed[:values],
          removed[:properties],
          nil,
          removed[:invoice_display_name]
        )
      end
    end

    def unchanged?(previous, new_filter)
      return false if previous.nil?

      previous[:properties] == new_filter[:properties] &&
        previous[:invoice_display_name] == new_filter[:invoice_display_name]
    end

    def enqueue(charge, action, values, old_properties, new_properties, invoice_display_name)
      ChargeFilters::CascadeJob.perform_later(
        charge.id, action, values, old_properties, new_properties, invoice_display_name
      )
    end
  end
end
