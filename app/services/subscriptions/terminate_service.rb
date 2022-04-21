# frozen_string_literal: true

module Subscriptions
  class TerminateService < BaseService
    def initialize(subscription_id)
      super(nil)
      @subscription = Subscription.find_by(id: subscription_id)
    end

    def terminate
      return result.fail!('not_found') if subscription.blank?

      unless subscription.terminated?
        subscription.mark_as_terminated!

        BillSubscriptionJob
          .perform_later(subscription, subscription.terminated_at)
      end

      result.subscription = subscription
      result
    end

    private

    attr_reader :subscription
  end
end
