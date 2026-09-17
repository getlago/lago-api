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

      delegate :all_filter_values?,
        :billable_metric,
        :filter_match_values,
        :filter_specificity,
        :filter_values,
        :filters,
        :selected_filter,
        :target_key,
        :with_filter,
        to: :source
    end
  end
end
