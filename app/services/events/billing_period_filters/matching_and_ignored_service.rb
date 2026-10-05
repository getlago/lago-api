# frozen_string_literal: true

module Events
  module BillingPeriodFilters
    class MatchingAndIgnoredService < BaseService
      Result = BaseResult[:matching_filters, :ignored_filters]

      def initialize(target_filter:)
        @target_filter = target_filter
        super
      end

      def call
        result.matching_filters = target_filter.filter_values(target_filter.selected_filter)

        ignored_filters = target_filter.charge? ? preceding_filters : child_filters
        result.ignored_filters = MinimizeIgnoredFiltersService.call(ignored_filters:).ignored_filters

        result
      end

      private

      attr_reader :target_filter

      def other_filters
        @other_filters ||= target_filter.filters.reject { it.id == target_filter.selected_filter.id }
      end

      # An event matching several charge filters is billed on the one EventMatchingService picks, so
      # the selected filter ignores every overlapping filter taking precedence over it.
      def preceding_filters
        selected_precedence = target_filter.filter_precedence(target_filter.selected_filter)

        other_filters.filter_map do |filter|
          next unless (target_filter.filter_precedence(filter) <=> selected_precedence).negative?

          child = target_filter.filter_values(filter)
          child if overlapping?(child)
        end
      end

      def overlapping?(child)
        child.all? do |key, values|
          !result.matching_filters.key?(key) || values.intersect?(result.matching_filters[key])
        end
      end

      def child_filters
        children = other_filters.find_all do |filter|
          child = target_filter.filter_values(filter)

          result.matching_filters.all? do |key, values|
            values.any? { (child[key] || []).include?(it) }
          end
        end

        children.map do |child_filter|
          child = target_filter.filter_values(child_filter).dup

          if child.keys.sort == result.matching_filters.keys.sort
            if identical_to_matching_filters?(child)
              next unless older_than_filter?(child_filter)
            elsif !subset_of_matching_filters?(child)
              child.each do |key, values|
                next if target_filter.all_filter_values?(target_filter.selected_filter, key)

                child[key] = values - result.matching_filters[key]
              end
            end
          end

          child
        end.compact
      end

      def subset_of_matching_filters?(child)
        child.all? { |key, values| (values - result.matching_filters[key]).empty? }
      end

      def identical_to_matching_filters?(child)
        child.all? { |key, values| values.sort == result.matching_filters[key].sort }
      end

      def older_than_filter?(child)
        return true if target_filter.selected_filter.created_at.nil?

        ([child.created_at, child.id] <=> [target_filter.selected_filter.created_at, target_filter.selected_filter.id]).negative?
      end
    end
  end
end
