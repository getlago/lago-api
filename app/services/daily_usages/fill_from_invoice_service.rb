# frozen_string_literal: true

module DailyUsages
  class FillFromInvoiceService < BaseService
    def initialize(invoice:, subscriptions:)
      @invoice = invoice
      @subscriptions = subscriptions

      super
    end

    def call
      result.daily_usages = []

      invoice.invoice_subscriptions.each do |invoice_subscription|
        subscription = subscriptions.find { |s| s.id == invoice_subscription.subscription_id }
        next if subscription.blank?
        next if existing_daily_usage(invoice_subscription).present?

        usage = invoice_usage(subscription, invoice_subscription)

        daily_usage = DailyUsage.new(
          organization: invoice.organization,
          customer: invoice.customer,
          subscription: subscription,
          external_subscription_id: subscription.external_id,
          usage: ::V1::Customers::UsageSerializer.new(usage, includes: %i[charges_usage]).serialize,
          from_datetime: invoice_subscription.from_datetime,
          to_datetime: invoice_subscription.to_datetime,
          refreshed_at: invoice_subscription.timestamp,
          usage_date: invoice_subscription.charges_to_datetime.to_date
        )

        daily_usage.usage_diff = diff_usage(daily_usage)
        daily_usage.save!

        result.daily_usages << daily_usage
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :invoice, :subscriptions

    def invoice_usage(subscription, invoice_subscription)
      OpenStruct.new(
        from_datetime: invoice_subscription.from_datetime,
        to_datetime: invoice_subscription.to_datetime,
        issuing_date: invoice.issuing_date.iso8601,
        currency: invoice.currency,
        amount_cents: invoice.fees_amount_cents,
        total_amount_cents: invoice.fees.sum(&:total_amount_cents),
        taxes_amount_cents: invoice.fees.sum(:taxes_amount_cents),
        fees: invoice.fees.charge.select { |f| f.subscription_id == subscription.id }
      )
    end

    def diff_usage(daily_usage)
      DailyUsages::ComputeDiffService.call!(daily_usage:).usage_diff
    end

    def existing_daily_usage(invoice_subscription)
      DailyUsage.find_by(
        from_datetime: invoice_subscription.from_datetime,
        to_datetime: invoice_subscription.to_datetime,
        usage_date: invoice_subscription.charges_to_datetime.to_date,
        subscription_id: invoice_subscription.subscription_id
      )
    end
  end
end
