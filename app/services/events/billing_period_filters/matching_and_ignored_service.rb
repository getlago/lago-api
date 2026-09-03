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

        children = other_filters.find_all do |filter|
          child = target_filter.filter_values(filter)

          result.matching_filters.all? do |key, values|
            values.any? { (child[key] || []).include?(it) }
          end
        end

        result.ignored_filters = children.map do |child_filter|
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

        result
      end

      private

      attr_reader :target_filter

      def other_filters
        @other_filters ||= target_filter.filters.reject { it.id == target_filter.selected_filter.id }
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
