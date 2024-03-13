# frozen_string_literal: true

module ChargeFilters
  class MatchingAndIgnoredService < BaseService
    def initialize(filter:)
      @filter = filter
      super
    end

    def call
      result.matching_filters = filter.to_h

      children = other_filters.find_all do |f|
        # NOTE: Check if filters contains all key/values from input filter
        (result.matching_filters.to_a - f.to_h.to_a).empty?
      end

      # NOTE: List of filters that we must ignore to prevent duplicated count of events
      result.ignored_filters = children.map do |child|
        (child.to_h.to_a - result.matching_filters.to_a).to_h
      end.flatten.first

      result
    end

    private

    attr_reader :filter

    delegate :charge, to: :filter

    def other_filters
      @other_filters ||= charge.filters.where.not(id: filter.id)
    end
  end
end
