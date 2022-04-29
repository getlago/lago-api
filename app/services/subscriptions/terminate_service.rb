# frozen_string_literal: true

module Subscriptions
  class TerminateService < BaseService
    def terminate(subscription_id)
      subscription = Subscription.find_by(id: subscription_id)
      return result.fail!('not_found') if subscription.blank?

      process_terminate(subscription)
    end

    def terminate_from_api(organization:, customer_id:)
      customer = organization.customers.find_by(customer_id: customer_id)
      return result.fail!('not_found') if customer.blank?

      subscription = customer.active_subscription
      return result.fail!('no_active_subscription') if subscription.blank?

      process_terminate(subscription)
    end

    private

    def process_terminate(subscription)
      unless subscription.terminated?
        subscription.mark_as_terminated!

        BillSubscriptionJob
          .perform_later(subscription, subscription.terminated_at)
      end

      result.subscription = subscription
      result
    end
  end
end
