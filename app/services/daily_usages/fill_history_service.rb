# frozen_string_literal: true

require "timecop"

module DailyUsages
  class FillHistoryService < BaseService
    def initialize(subscription:, from_date:, to_date: nil, sandbox: false)
      @subscription = subscription
      @from_date = from_date
      @to_date = to_date
      @sandbox = sandbox

      super
    end

    def call
      previous_daily_usage = nil

      (from..to).each do |date|
        next if !sandbox && subscription.daily_usages.where(usage_date: date).exists?

        datetime = date.in_time_zone(subscription.customer.applicable_timezone).beginning_of_day.utc
        datetime = date.beginning_of_day.utc if datetime < date # Handle last day for timezone with positive offset

        Timecop.thread_safe = true
        time_to_freeze = datetime.in_time_zone(subscription.customer.applicable_timezone).end_of_day
        Timecop.freeze(time_to_freeze) do
          usage = Invoices::CustomerUsageService.call(
            customer: subscription.customer,
            subscription: subscription,
            apply_taxes: false,
            with_cache: false,
            max_timestamp: time_to_freeze,
            with_zero_units_filters: false
          ).raise_if_error!.usage
          next if sandbox

          if previous_daily_usage.present? && previous_daily_usage.from_datetime != usage.from_datetime
            # NOTE: A new billing period was started, the diff should contains the complete current usage
            previous_daily_usage = nil
          end

          if usage.total_amount_cents.positive?
            usage.fees = usage.fees.select { |f| f.units.positive? }

            daily_usage = DailyUsage.new(
              organization:,
              customer: subscription.customer,
              subscription:,
              external_subscription_id: subscription.external_id,
              usage: ::V1::Customers::UsageSerializer.new(usage, includes: %i[charges_usage]).serialize,
              from_datetime: usage.from_datetime,
              to_datetime: usage.to_datetime,
              refreshed_at: datetime,
              usage_diff: {},
              usage_date: date
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

    attr_reader :subscription, :from_date, :to_date, :sandbox
    delegate :organization, to: :subscription

    def from
      @from ||= [
        subscription.started_at.in_time_zone(timezone).to_date,
        from_date
      ].max
    end

    def to
      @to ||= if subscription.terminated?
        subscription.terminated_at.in_time_zone(timezone).to_date
      else
        to_date || Time.zone.yesterday.in_time_zone(timezone).to_date
      end
    end

    def timezone
      @timezone ||= subscription.customer.applicable_timezone
    end
  end
end
