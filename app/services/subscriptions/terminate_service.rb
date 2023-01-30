# frozen_string_literal: true

module Subscriptions
  class TerminateService < BaseService
    def self.call(...)
      new(...).call
    end

    def initialize(subscription:)
      @subscription = subscription

      super
    end

    def call
      return result.not_found_failure!(resource: 'subscription') if subscription.blank?

      if subscription.starting_in_the_future?
        subscription.mark_as_terminated!
      elsif !subscription.terminated?
        subscription.mark_as_terminated!

        if subscription.plan.pay_in_advance?
          # NOTE: As subscription was payed in advance and terminated before the end of the period,
          #       we have to create a credit note for the days that were not consumed
          credit_note_result = CreditNotes::CreateFromTermination.new(
            subscription:,
            reason: 'order_cancellation',
          ).call
          credit_note_result.raise_if_error!
        end

        BillSubscriptionJob.perform_later([subscription], subscription.terminated_at)
      end

      # NOTE: Pending next subscription should be canceled as well
      subscription.next_subscription&.mark_as_canceled!

      SendWebhookJob.perform_later(
        'subscription.terminated',
        subscription,
      )

      result.subscription = subscription
      result
    end

    # NOTE: Called to terminate a downgraded subscription
    def terminate_and_start_next(timestamp:)
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

      SendWebhookJob.perform_later(
        'subscription.terminated',
        subscription,
      )

      result.subscription = next_subscription
      return result unless next_subscription.plan.pay_in_advance?

      BillSubscriptionJob.perform_later(
        [next_subscription],
        timestamp,
      )

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :subscription
  end
end
