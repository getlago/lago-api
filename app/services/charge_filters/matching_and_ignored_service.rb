# frozen_string_literal: true

module ChargeFilters
  class MatchingAndIgnoredService < BaseService
    def initialize(filter:)
      @filter = filter
      super
    end

    def call
      result.matching_filters = filter.to_h

      # NOTE: Check if filters contains some key/values from input filter
      children = other_filters.find_all do |f|
        child = f.to_h

        result.matching_filters.all? do |key, values|
          values.any? { (child[key] || []).include?(_1) }
        end
      end

      # NOTE: List of filters that we must ignore to prevent duplicated count of events
      result.ignored_filters = children.each_with_object([]) do |child_filter, res|
        child = child_filter.to_h
        child_result = {}

        child.each do |key, values|
          # NOTE: The parent filter does not have the key, so we ignore all values
          next child_result[key] = values unless result.matching_filters[key]

          # NOTE: The parent filter, has the same values for the key, so no need to filter them
          next if values == result.matching_filters[key]

          # NOTE: The parent filter has some values for the key, so we get only the parent ones
          child_result[key] = values.select { result.matching_filters[key].include?(_1) }
        end

        res << child_result
      end.uniq

      result
    end

    private

    attr_reader :filter

    delegate :charge, to: :filter

    def other_filters
      @other_filters ||= charge.filters.where.not(id: filter.id).includes(values: :billable_metric_filter)
    end
  end
end
