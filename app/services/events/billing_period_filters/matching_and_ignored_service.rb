# frozen_string_literal: true

module Events
  module BillingPeriodFilters
    class MatchingAndIgnoredService < BaseService
      Result = BaseResult[:matching_filters, :ignored_filters]

      def initialize(target_filter:)
        @target_filter = target_filter
        super
      end

      # An event matching several filters is billed on the one EventMatchingService picks, so the
      # selected filter ignores every overlapping filter taking precedence over it.
      def call
        result.matching_filters = target_filter.filter_values(target_filter.selected_filter)

        ignored_filters = other_filters.filter_map do |filter|
          next unless preceding?(filter)

          child = target_filter.filter_values(filter)
          child if overlapping?(child)
        end

        result.ignored_filters = MinimizeIgnoredFiltersService.call(ignored_filters:).ignored_filters

        result
      end

      private

      attr_reader :target_filter

      def other_filters
        @other_filters ||= target_filter.filters.reject { it.id == target_filter.selected_filter.id }
      end

      def preceding?(filter)
        (target_filter.filter_precedence(filter) <=> selected_precedence).negative?
      end

      def selected_precedence
        @selected_precedence ||= target_filter.filter_precedence(target_filter.selected_filter)
      end

      def overlapping?(child)
        child.all? do |key, values|
          !result.matching_filters.key?(key) || values.intersect?(result.matching_filters[key])
        end
      end
    end
  end
end
