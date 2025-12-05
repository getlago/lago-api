# frozen_string_literal: true

module Events
  class BillingPeriodFilterService < BaseService
    Result = BaseResult[:charge_ids]

    def initialize(subscription:, boundaries:)
      @subscription = subscription
      @boundaries = boundaries
      super
    end

    def call
      values = plan.charges.joins(:billable_metric)
        .where(billable_metrics: {code: distinct_event_codes})
        .or(plan.charges.joins(:billable_metric).where(billable_metrics: {recurring: true}))
        .pluck("DISTINCT(charges.id)")

      result.charge_ids = values

      result
    end

    private

    attr_reader :subscription, :boundaries

    delegate :plan, to: :subscription

    def distinct_event_codes
      Events::Stores::StoreFactory.new_instance(
        organization: subscription.organization,
        subscription:,
        boundaries: {
          from_datetime: boundaries.charges_from_datetime,
          to_datetime: boundaries.charges_to_datetime
        }
      ).distinct_codes
    end
  end
end
