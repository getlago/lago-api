# frozen_string_literal: true

module ChargeFilters
  class EventMatchingService < BaseService
    Result = BaseResult[:matching_charge_filters, :charge_filter]

    def initialize(charge:, event:)
      @charge = charge
      @event = event

      super
    end

    def call
      matching_result = Events::BillingPeriodFilters::EventMatchingService.call(
        target_filter: Events::BillingPeriodFilters::FilterTarget.from_charge(charge:),
        event:
      )

      result.matching_charge_filters = matching_result.matching_filters
      result.charge_filter = matching_result.filter
      result
    end

    private

    attr_reader :charge, :event
  end
end
