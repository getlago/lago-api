# frozen_string_literal: true

module Subscriptions
  class TerminateService < BaseService
    def initialize(subscription:, async: true)
      @subscription = subscription
      @async = async

      super
    end

    def call
      return result.not_found_failure!(resource: 'subscription') if subscription.blank?

      if subscription.starting_in_the_future?
        subscription.mark_as_terminated!
      elsif subscription.pending?
        subscription.mark_as_canceled!
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

        bill_subscription
      end

      # NOTE: Pending next subscription should be canceled as well
      subscription.next_subscription&.mark_as_canceled!

      # NOTE: Wait to ensure job is performed at the end of the database transaction.
      # See https://github.com/getlago/lago-api/blob/main/app/services/subscriptions/create_service.rb#L46.
      SendWebhookJob.set(wait: 2.seconds).perform_later('subscription.terminated', subscription)

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
      BillSubscriptionJob.perform_later([subscription], timestamp)

      SendWebhookJob.perform_later('subscription.terminated', subscription)
      SendWebhookJob.perform_later('subscription.started', next_subscription)

      result.subscription = next_subscription
      return result unless next_subscription.plan.pay_in_advance?

      BillSubscriptionJob.perform_later([next_subscription], timestamp)

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :subscription, :async

    def bill_subscription
      if async
        # NOTE: Wait to ensure job is performed at the end of the database transaction.
        # See https://github.com/getlago/lago-api/blob/main/app/services/subscriptions/create_service.rb#L46.
        BillSubscriptionJob.set(wait: 2.seconds).perform_later([subscription], subscription.terminated_at)
      else
        BillSubscriptionJob.perform_now([subscription], subscription.terminated_at)
      end
    end
  end
end
