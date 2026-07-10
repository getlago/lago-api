# frozen_string_literal: true

module ChargeFilters
  class MatchingAndIgnoredService < BaseService
    Result = BaseResult[:matching_filters, :ignored_filters]

    def initialize(charge:, filter:)
      @charge = charge
      @filter = filter
      super
    end

    def call
      result.matching_filters = filter.to_h_with_all_values

      # NOTE: Check if filters contains some key/values from input filter
      #       Result will have the following format:
      #       {
      #         key1: [value1, value2],
      #         key2: [value3, value4]
      #       }
      children = other_filters.find_all do |f|
        child = f.to_h_with_all_values

        result.matching_filters.all? do |key, values|
          values.any? { (child[key] || []).include?(it) }
        end
      end

      # NOTE: List of filters that we must ignore to prevent duplicated count of events
      #       Result will have the following format:
      #       [
      #         {
      #           key1: [value1],
      #           key2: [value3, value4]
      #         },
      #         {
      #           key1: [value2],
      #           key2: [value3, value4]
      #         }
      #       ]
      result.ignored_filters = children.map do |child|
        res = child.to_h_with_all_values.dup

        # NOTE: when child and filter have the same keys, we need to remove the filter value from the child.
        #       When the child's values are a subset of the filter's values on every key, the child is kept
        #       verbatim so that its events are excluded from the filter's bucket instead of being counted twice.
        if res.keys == result.matching_filters.keys && !subset_of_matching_filters?(res)
          res.each do |key, values|
            next if filter.to_h[key] == [ChargeFilterValue::ALL_FILTER_VALUES]

            res[key] = values - result.matching_filters[key]
          end
        end

        res
      end.compact

      result
    end

    private

    attr_reader :charge, :filter

    def other_filters
      @other_filters ||= charge.filters.select { it.id != filter.id }
    end

    def subset_of_matching_filters?(child)
      child.all? { |key, values| (values - result.matching_filters[key]).empty? }
    end
  end
end
