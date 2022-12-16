# frozen_string_literal: true

module Subscriptions
  class UpdateService < BaseService
    def update(subscription:, args:)
      return result.not_found_failure!(resource: 'subscription') unless subscription

      subscription.name = args[:name] if args.key?(:name)

      if subscription.starting_in_the_future? && args.key?(:subscription_at)
        subscription.subscription_at = args[:subscription_at]

        process_subscription_at_change(subscription)
      else
        subscription.save!
      end

      result.subscription = subscription
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    def process_subscription_at_change(subscription)
      if subscription.subscription_at <= Time.current
        subscription.mark_as_active!(subscription.subscription_at)
      else
        subscription.save!
      end

      return unless subscription.plan.pay_in_advance? && subscription.subscription_at.today?

      BillSubscriptionJob.perform_later([subscription], Time.current.to_i)
    end
  end
end
