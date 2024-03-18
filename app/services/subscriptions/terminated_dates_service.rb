# frozen_string_literal: true

module Subscriptions
  class TerminatedDatesService
    def initialize(subscription:, invoice:, date_service:)
      @subscription = subscription
      @timestamp = invoice.invoice_subscriptions.first&.timestamp
      @date_service = date_service
    end

    def call
      return date_service unless subscription.terminated? && subscription.next_subscription.nil?

      # First we need to ensure that termination date is not started_at date. In that case boundaries are correct
      # and we should bill only one day. If this is not the case we should proceed.
      return date_service if (timestamp - 1.day) < subscription.started_at

      # Date service has various checks for terminated subscriptions. We want to avoid it and fetch boundaries
      # for current usage (current period) but when subscription was active (one day ago)
      duplicate = subscription.dup.tap { |s| s.status = :active }
      new_dates_service = Subscriptions::DatesService.new_instance(duplicate, timestamp - 1.day, current_usage: true)

      return date_service if timestamp < new_dates_service.charges_to_datetime
      return date_service unless (timestamp - new_dates_service.charges_to_datetime) < 1.day

      # We should calculate boundaries as if subscription was not terminated
      new_dates_service = Subscriptions::DatesService.new_instance(duplicate, timestamp, current_usage: false)

      matching_invoice_subscription?(subscription, new_dates_service) ? date_service : new_dates_service
    end

    private

    attr_reader :subscription, :timestamp, :date_service

    def matching_invoice_subscription?(subscription, date_service)
      base_query = InvoiceSubscription
        .where(subscription_id: subscription.id)
        .recurring
        .where(from_datetime: date_service.from_datetime)
        .where(to_datetime: date_service.to_datetime)

      if subscription.plan.yearly? && subscription.plan.bill_charges_monthly?
        base_query = base_query
          .where(charges_from_datetime: date_service.charges_from_datetime)
          .where(charges_to_datetime: date_service.charges_to_datetime)
      end

      base_query.exists?
    end
  end
end
