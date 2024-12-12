# frozen_string_literal: true

require "timecop"

module DailyUsages
  class FillHistoryService < BaseService
    def initialize(subscription:, from_datetime:)
      @subscription = subscription
      @from_datetime = from_datetime

      super
    end

    def call
      previous_daily_usage = nil

      (from..to).each do |date|
        datetime = date.in_time_zone(subscription.customer.applicable_timezone).beginning_of_day.utc

        next if date == Time.zone.today ||
          DailyUsage.refreshed_at_in_timezone(datetime).where(subscription_id: subscription.id).exists?

        Timecop.thread_safe = true
        Timecop.freeze(datetime + 5.minutes) do
          usage = Invoices::CustomerUsageService.call(
            customer: subscription.customer,
            subscription: subscription,
            apply_taxes: false,
            with_cache: false,
            max_to_datetime: datetime
          ).raise_if_error!.usage

          if previous_daily_usage.present? && previous_daily_usage.from_datetime != usage.from_datetime
            # NOTE: A new billing period was started, the diff should contains the complete current usage
            previous_daily_usage = nil
          end

          daily_usage = DailyUsage.new(
            organization:,
            customer: subscription.customer,
            subscription:,
            external_subscription_id: subscription.external_id,
            usage: ::V1::Customers::UsageSerializer.new(usage, includes: %i[charges_usage]).serialize,
            from_datetime: usage.from_datetime,
            to_datetime: usage.to_datetime,
            refreshed_at: datetime,
            usage_diff: {}
          )

          if date != from
            daily_usage.usage_diff = DailyUsages::ComputeDiffService
              .call(daily_usage:, previous_daily_usage:)
              .raise_if_error!
              .usage_diff
          end

          daily_usage.save!

          previous_daily_usage = daily_usage
        end
      end

      if subscription.terminated?
        invoice = subscription.invoices
          .joins(:invoice_subscriptions)
          .where(invoice_subscriptions: {invoicing_reason: "subscription_terminating"})
          .first

        if invoice.present?
          DailyUsages::FillFromInvoiceJob.perform_later(invoice:, subscriptions: [subscription])
        end
      end

      result
    end

    attr_reader :subscription, :from_datetime
    delegate :organization, to: :subscription

    def from
      return @from if defined?(@from)

      @from = subscription.started_at.to_date
      @from = from_datetime.to_date if @from < from_datetime
      @from
    end

    def to
      @to ||= (subscription.terminated_at || Time.current).to_date
    end
  end
end
