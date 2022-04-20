# frozen_string_literal: true

module Subscriptions
  class TerminateService < BaseService
    def initialize(subscription_id)
      super(nil)
      @subscription = Subscription.find_by(id: subscription_id)
    end

    def terminate
      return result.fail!('not_found') unless subscription.present?

      subscription.mark_as_terminated!

      # TODO: Bill what has to be billed when terminated

      result.subscription = subscription
      result
    end

    private

    attr_reader :subscription
  end
end
