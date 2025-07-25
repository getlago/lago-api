# frozen_string_literal: true

require "timecop"

module DailyUsages
  class FillHistoryService < BaseService
    def initialize(subscription:, from_datetime:, to_datetime: nil, sandbox: false)
      @subscription = subscription
      @from_datetime = from_datetime
      @to_datetime = to_datetime
      @sandbox = sandbox

      super
    end

    def call
      previous_daily_usage = nil

      (from..to).each do |date|
        datetime = date.beginning_of_day
        next if !sandbox && subscription.daily_usages.where(usage_date: datetime.to_date).exists?

        Timecop.thread_safe = true
        Timecop.freeze(datetime) do
          usage = Invoices::CustomerUsageService.call(
            customer: subscription.customer,
            subscription: subscription,
            apply_taxes: false,
            with_cache: false,
            max_to_datetime: datetime.in_time_zone(subscription.customer.applicable_timezone).end_of_day
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
              refreshed_at: datetime.end_of_day,
              usage_diff: {},
              usage_date: datetime.to_date
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

    attr_reader :subscription, :from_datetime, :to_datetime, :sandbox
    delegate :organization, to: :subscription

    def from
      return @from if defined?(@from)

      @from = subscription.started_at.to_date
      @from = from_datetime.to_date if @from < from_datetime
      @from
    end

    def to
      @to ||= if subscription.terminated?
        subscription.terminated_at.to_date
      else
        (to_datetime || Time.current).to_date
      end
    end
  end
end
