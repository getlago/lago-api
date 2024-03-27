# frozen_string_literal: true

module ChargeFilters
  class EventMatchingService < BaseService
    def initialize(charge:, event:)
      @charge = charge
      @event = event

      super
    end

    def call
      # NOTE: Find all filters matching event properties
      matching_filters = filters.all.select do |filter|
        filter.to_h.all? do |key, values|
          applicable_event_properties.key?(key) && applicable_event_properties[key].in?(values)
        end
      end

      # NOTE: An event could match multiple filters,
      #       but we must take only the one matching the most properties
      result.charge_filter = matching_filters.max_by { |filter| filter.to_h.keys.size }
      result
    end

    private

    attr_reader :charge, :event

    # NOTE: Exclude event properties not matching a billable metric filter
    def applicable_event_properties
      @applicable_event_properties ||= event.properties.slice(*charge.billable_metric.filters.pluck(:key))
    end

    def filters
      charge.filters.includes(values: :billable_metric_filter)
    end
  end
end
