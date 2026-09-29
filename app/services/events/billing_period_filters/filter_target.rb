# frozen_string_literal: true

module Events
  module BillingPeriodFilters
    FilterTarget = Data.define(:source) do
      def self.from_charge(charge:, filter: nil)
        new(source: Sources::Charge.new(charge:, filter:))
      end

      def self.from_billing_segment(billing_segment:, filter: nil)
        new(source: Sources::BillingSegment.new(billing_segment:, filter:))
      end

      delegate :billable_metric,
        :filter_match_values,
        :filter_values,
        :filters,
        :selected_filter,
        :target_key,
        :with_filter,
        to: :source

      # Sort key of the filter an event is billed on when several match it: the most keys, then the
      # fewest allowed values, then the oldest. An unsaved filter (the default bucket) comes last.
      def filter_precedence(filter)
        values = filter_values(filter)
        age = filter.created_at ? [0, filter.created_at, filter.id] : [1]

        [-values.size, values.sum { |_key, allowed| allowed.size }, age]
      end
    end
  end
end
