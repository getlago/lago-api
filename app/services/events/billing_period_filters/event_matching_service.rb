# frozen_string_literal: true

module Events
  module BillingPeriodFilters
    class EventMatchingService < BaseService
      Result = BaseResult[:matching_filters, :filter]

      def initialize(target_filter:, event:)
        @target_filter = target_filter
        @event = event

        super
      end

      def call
        matching_filters = target_filter.filters.select { |filter| matches?(filter) }

        result.matching_filters = matching_filters
        result.filter = matching_filters.max_by { |filter| target_filter.filter_specificity(filter) }
        result
      end

      private

      attr_reader :target_filter, :event

      def matches?(filter)
        target_filter.filter_values(filter).all? do |key, values|
          applicable_event_properties.key?(key) && applicable_event_properties[key].to_s.in?(values.map(&:to_s))
        end
      end

      def applicable_event_properties
        @applicable_event_properties ||= event.properties.slice(*billable_metric_filter_keys)
      end

      def billable_metric_filter_keys
        billable_metric = target_filter.billable_metric

        return billable_metric.filters.map(&:key) if billable_metric.association_cached?(:filters)

        billable_metric.filters.pluck(:key)
      end
    end
  end
end
