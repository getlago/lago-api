# frozen_string_literal: true

module Subscriptions
  class PayInAdvanceInvoiceIssuedService < BaseService
    Result = BaseResult[:issued]

    def initialize(subscription:, timestamp:)
      @subscription = subscription
      @timestamp = timestamp
      super
    end

    def call
      result.issued = issued?
      result
    end

    private

    attr_reader :subscription, :timestamp

    def issued?
      # A duplicate forced to active is used so the special cases for a terminated subscription are
      # avoided in the boundaries calculation.
      duplicate = subscription.dup.tap { |s| s.status = :active }
      period_start = beginning_of_period(duplicate)

      # If this is the first period, the pay-in-advance invoice was issued when the subscription was
      # created.
      return true if period_start < duplicate.started_at

      dates_service = Subscriptions::DatesService.new_instance(duplicate, period_start, current_usage: false)

      boundaries = BillingPeriodBoundaries.new(
        from_datetime: dates_service.from_datetime,
        to_datetime: dates_service.to_datetime,
        charges_from_datetime: dates_service.charges_from_datetime,
        charges_to_datetime: dates_service.charges_to_datetime,
        charges_duration: dates_service.charges_duration_in_days,
        timestamp: period_start
      )

      InvoiceSubscription.matching?(subscription, boundaries, recurring: false)
    end

    def beginning_of_period(duplicate)
      dates_service = Subscriptions::DatesService.new_instance(duplicate, timestamp, current_usage: false)
      dates_service.previous_beginning_of_period(current_period: true).to_datetime
    end
  end
end
