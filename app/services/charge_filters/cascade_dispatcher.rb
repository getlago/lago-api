# frozen_string_literal: true

module ChargeFilters
  module CascadeDispatcher
    module_function

    # Diffs `before` against `after` and enqueues one ChargeFilters::CascadeJob
    # per change. `before` and `after` are arrays of:
    #   { values: {"key" => [...]}, properties: {...} | nil, invoice_display_name: "...",
    #     code: "..." | nil }
    # `values` and `properties` must be string-keyed.
    #
    # A plan edit never gives a filter a code it did not have, so a filter is either coded on
    # both sides of the diff or on neither, and the split cannot cut one in half.
    def call(charge:, before:, after:)
      coded_before, plain_before = before.partition { it[:code].present? }
      coded_after, plain_after = after.partition { it[:code].present? }

      diff_by_code(charge, coded_before, coded_after)
      diff_by_predicate(charge, plain_before, plain_after)
    end

    def diff_by_code(charge, before, after)
      before_by_code = before.index_by { it[:code] }

      after.each do |new_filter|
        previous = before_by_code.delete(new_filter[:code])
        next if previous && unchanged?(previous, new_filter)

        enqueue_change(charge, previous ? "update" : "create", new_filter, previous&.dig(:properties))
      end

      before_by_code.each_value { enqueue_destroy(charge, it) }
    end

    # The legacy path, for the filters the backfill left without a code. Two of them can share a
    # predicate once a metric change shortened them onto it, and this keeps one: nothing here can
    # tell them apart. Delete it once no filter is left without a code.
    def diff_by_predicate(charge, before, after)
      before_by_values = before.index_by { it[:values] }

      after.each do |new_filter|
        previous = before_by_values.delete(new_filter[:values])
        next if previous && unchanged?(previous, new_filter)

        enqueue_change(charge, previous ? "update" : "create", new_filter, previous&.dig(:properties))
      end

      before_by_values.each_value { enqueue_destroy(charge, it) }
    end

    def unchanged?(previous, new_filter)
      previous[:properties] == new_filter[:properties] &&
        previous[:invoice_display_name] == new_filter[:invoice_display_name]
    end

    def enqueue_change(charge, action, filter, old_properties)
      ChargeFilters::CascadeJob.perform_later(
        charge.id, action, filter[:values], old_properties,
        filter[:properties], filter[:invoice_display_name], filter[:code]
      )
    end

    def enqueue_destroy(charge, filter)
      ChargeFilters::CascadeJob.perform_later(
        charge.id, "destroy", filter[:values], filter[:properties],
        nil, filter[:invoice_display_name], filter[:code]
      )
    end
  end
end
