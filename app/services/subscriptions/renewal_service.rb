# frozen_string_literal: true

module Subscriptions
  class RenewalService < BaseService
    def initialize(timebased_event:, async: false)
      @timebased_event = timebased_event
      @async = async
      super
    end

    def call
      if already_renewed?
        result.already_renewed = true
        return result
      end

      billing_result = bill_subscription

      if !async && billing_result.success?
        timebased_event.update(invoice: billing_result.invoice)
      end

      result.timebased_event = timebased_event
      result
    end

    # private

    attr_reader :timebased_event, :async

    def subscription
      @subscription ||= Subscription.find_by(external_id: timebased_event.external_subscription_id)
    end

    def already_renewed?
      # TODO: should compare in the same timezone
      InvoiceSubscription
        .where(subscription: subscription)
        .where(
          "from_datetime <= ? AND to_datetime >= ?", timebased_event.timestamp, timebased_event.timestamp
        ).exists?
    end

    def billing_timestamp
      @billing_timestamp ||= Time.current.to_i
    end

    def bill_subscription
      if async
        BillSubscriptionByTimebasedEventJob.perform_later(
          subscription,
          billing_timestamp,
          async:,
        )
      else
        BillSubscriptionByTimebasedEventJob.perform_now(
          subscription,
          billing_timestamp,
          async:,
        )
      end
    end
  end
end
