# frozen_string_literal: true

module Subscriptions
  class TerminateService < BaseService
    def terminate(subscription_id)
      subscription = Subscription.find_by(id: subscription_id)
      return result.fail!(code: 'not_found') if subscription.blank?

      process_terminate(subscription)
    end

    def terminate_from_api(organization:, subscription_id:)
      subscription = organization.subscriptions.find_by(id: subscription_id)
      return result.fail!(code: 'not_found', message: 'subscription is not found') if subscription.blank?

      process_terminate(subscription)
    end

    # NOTE: Called to terminate a downgraded subscription
    def terminate_and_start_next(subscription:, timestamp:)
      next_subscription = subscription.next_subscription
      return result unless next_subscription
      return result unless next_subscription.pending?

      rotation_date = Time.zone.at(timestamp)

      ActiveRecord::Base.transaction do
        subscription.mark_as_terminated!(rotation_date)
        next_subscription.mark_as_active!(rotation_date)
      end

      # NOTE: Create an invoice for the terminated subscription
      #       if it has not been billed yet
      #       or only for the charges if subscription was billed in advance
      BillSubscriptionJob.perform_later(
        [subscription],
        timestamp,
      )

      result.subscription = next_subscription
      return result unless next_subscription.plan.pay_in_advance?

      BillSubscriptionJob.perform_later(
        [next_subscription],
        timestamp,
      )

      result
    rescue ActiveRecord::RecordInvalid => e
      result.fail_with_validations!(e.record)
    end

    private

    def process_terminate(subscription)
      unless subscription.terminated?
        subscription.mark_as_terminated!

        BillSubscriptionJob
          .perform_later([subscription], subscription.terminated_at)
      end

      # NOTE: Pending next subscription should be canceled as well
      subscription.next_subscription&.mark_as_canceled!

      result.subscription = subscription
      result
    end
  end
end
