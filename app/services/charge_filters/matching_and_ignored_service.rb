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
      matching_result = Events::BillingPeriodFilters::MatchingAndIgnoredService.call(
        target_filter: Events::BillingPeriodFilters::FilterTarget.from_charge(charge:, filter:)
      )

      result.matching_filters = matching_result.matching_filters
      result.ignored_filters = matching_result.ignored_filters

      result
    end

    private

    attr_reader :charge, :filter
  end
end
