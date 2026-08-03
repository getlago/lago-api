# frozen_string_literal: true

module ChargeFilters
  module CascadeDispatcher
    module_function

    # Diffs `before` against `after` and enqueues one ChargeFilters::CascadeJob
    # per change. `before` and `after` are arrays of:
    #   { values: {"key" => [...]}, properties: {...} | nil, invoice_display_name: "..." }
    # `values` and `properties` must be string-keyed.
    def call(charge:, before:, after:)
      removed = before.group_by { |filter| filter[:values] }

      after.each do |new_filter|
        previous = removed.delete(new_filter[:values])&.first

        next if unchanged?(previous, new_filter)

        enqueue(
          charge,
          previous ? "update" : "create",
          new_filter[:values],
          previous&.dig(:properties),
          new_filter[:properties],
          new_filter[:invoice_display_name]
        )
      end

      removed.each_value do |old_filters|
        old_filter = old_filters.first

        enqueue(
          charge,
          "destroy",
          old_filter[:values],
          old_filter[:properties],
          nil,
          old_filter[:invoice_display_name]
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
