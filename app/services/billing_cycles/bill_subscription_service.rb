# frozen_string_literal: true

module BillingCycles
  # Bills a customer's due items on demand by running both outbox lanes for them in one
  # pass (schedule -> process). Used right after subscription creation so advance items
  # invoice immediately instead of waiting for the clock tick; the clock does the same,
  # just periodically. Scoped to the subscription's customer, so items due on the same
  # boundary consolidate onto one invoice. Arrears items aren't due yet, so they wait.
  class BillSubscriptionService < BaseService
    Result = BaseResult[:invoices]

    def initialize(subscription:, up_to: Time.current)
      @subscription = subscription
      @up_to = up_to
      super
    end

    def call
      ScheduleService.call(customer:, up_to:)
      result.invoices = ProcessService.call(customer:).invoices
      result
    end

    private

    attr_reader :subscription, :up_to

    def customer
      subscription.customer
    end
  end
end
