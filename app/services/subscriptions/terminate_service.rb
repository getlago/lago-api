# frozen_string_literal: true

module Subscriptions
  class TerminateService < BaseService
    def initialize(subscription_id)
      super(nil)
      @subscription = Subscription.find_by(id: subscription_id)
    end

    def terminate
      return result.fail!('not_found') if subscription.blank?

      subscription.mark_as_terminated!

      BillSubscriptionJob
        .set(wait: rand(240).minutes)
        .perform_later(subscription, subscription.terminated_at)

      result.subscription = subscription
      result
    end

    private

    attr_reader :subscription
  end
end
