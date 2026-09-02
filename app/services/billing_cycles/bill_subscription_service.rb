# frozen_string_literal: true

module BillingCycles
  # Bills a customer's due items on demand by running both outbox lanes for them in one
  # pass (schedule -> process). Used right after subscription creation so advance items
  # invoice immediately instead of waiting for the clock tick; the clock does the same,
  # just periodically. Scoped to the subscription's customer, so items due on the same
  # boundary consolidate onto one invoice. Arrears items aren't due yet, so they wait.
  class BillSubscriptionService < BaseService
    Result = BaseResult[:invoices]

    def initialize(subscription:, range: nil)
      @subscription = subscription
      @range = range
      super
    end

    def call
      schedule = ScheduleService.call(customer:, range:)
      return result.fail_with_error!(schedule.error) if schedule.failure?

      result.invoices = ProcessService.call(customer:).invoices
      result
    end

    private

    attr_reader :subscription, :range

    def customer
      subscription.customer
    end
  end
end
