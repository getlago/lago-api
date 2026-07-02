# frozen_string_literal: true

module ChargeFilters
  class MatchingAndIgnoredBatchService < BaseService
    Result = BaseResult[:filters_results]

    def initialize(charge:)
      @charge = charge
      super
    end

    # Returns, for every filter of the charge, the same matching_filters and ignored_filters
    # as ChargeFilters::MatchingAndIgnoredService, keyed by filter id.
    # Matching children are resolved through an inverted index of the charge filter values
    # (key => value => filters), built once for the whole charge, so the cost stays
    # proportional to the number of filter values instead of being quadratic in the number
    # of filters.
    def call
      result.filters_results = filters.each_with_index.to_h do |filter, position|
        [
          filter.id,
          {
            matching_filters: filter.to_h_with_all_values,
            ignored_filters: ignored_filters(filter, position)
          }
        ]
      end
      result
    end

    private

    attr_reader :charge

    def filters
      @filters ||= charge.filters.to_a
    end

    # Inverted index: key => value => positions of the filters carrying this value
    def values_index
      @values_index ||= filters.each_with_index.with_object({}) do |(filter, position), index|
        filter.to_h_with_all_values.each do |key, values|
          key_index = (index[key] ||= {})
          values.uniq.each { |value| (key_index[value] ||= []) << position }
        end
      end
    end

    # NOTE: Children are the filters sharing at least one value with the input filter
    #       for every key of the input filter
    def matching_children(filter, position)
      filter_all_values = filter.to_h_with_all_values

      # A filter without any value matches all its siblings
      if filter_all_values.empty?
        return filters.each_with_index.reject { |_, pos| pos == position }.map(&:first)
      end

      positions = nil
      filter_all_values.each do |key, values|
        key_positions = values.flat_map { |value| values_index.dig(key, value) || [] }.to_set
        positions = positions.nil? ? key_positions : positions & key_positions
        return [] if positions.empty?
      end

      positions.delete(position)
      positions.sort.map { |pos| filters[pos] }
    end

    # NOTE: List of filters that we must ignore to prevent duplicated count of events
    def ignored_filters(filter, position)
      filter_all_values = filter.to_h_with_all_values
      filter_values = filter.to_h

      matching_children(filter, position).map do |child|
        res = child.to_h_with_all_values.dup

        if res.keys == filter_all_values.keys
          # NOTE: when child and filter have the same keys, we need to remove the filter value from the child
          res.each do |key, values|
            next if filter_values[key] == [ChargeFilterValue::ALL_FILTER_VALUES]

            res[key] = values - filter_all_values[key]
          end
        end

        res
      end
    end
  end
end
