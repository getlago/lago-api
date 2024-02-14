# frozen_string_literal: true

module Commitments
  class HelperService < BaseService
    def initialize(commitment:, invoice_subscription:)
      @commitment = commitment
      @invoice_subscription = invoice_subscription

      super
    end

    def proration_coefficient
      result.proration_coefficient = calculate_proration_coefficient
      result
    end

    def period_invoice_ids
      result.period_invoice_ids = fetch_period_invoice_ids
      result
    end

    private

    attr_reader :commitment, :invoice_subscription

    delegate :subscription, to: :invoice_subscription

    def calculate_proration_coefficient
      all_invoice_subscriptions = subscription
        .invoice_subscriptions
        .where(invoice_id: fetch_period_invoice_ids)
        .order(
          Arel.sql(
            ActiveRecord::Base.sanitize_sql_for_conditions(
              'COALESCE(invoice_subscriptions.to_datetime, invoice_subscriptions.timestamp) ASC',
            ),
          ),
        )

      days = Utils::DatetimeService.date_diff_with_timezone(
        all_invoice_subscriptions.first.from_datetime,
        invoice_subscription.to_datetime,
        subscription.customer.applicable_timezone,
      )

      days_total = Utils::DatetimeService.date_diff_with_timezone(
        dates_service.previous_beginning_of_period,
        dates_service.end_of_period,
        subscription.customer.applicable_timezone,
      )

      days / days_total.to_f
    end

    def fetch_period_invoice_ids
      plan = subscription.plan

      return [invoice_subscription.invoice_id] if !subscription.plan.yearly? || !plan.bill_charges_monthly?

      subscription
        .invoice_subscriptions
        .where(
          'from_datetime >= ? AND to_datetime <= ?',
          dates_service.previous_beginning_of_period,
          dates_service.end_of_period,
        )
        .pluck(:invoice_id)
    end

    def dates_service
      ds = Subscriptions::DatesService.new_instance(
        subscription,
        invoice_subscription.timestamp,
        current_usage: subscription.terminated?,
      )

      return ds unless subscription.terminated?

      Invoices::CalculateFeesService.new(invoice: invoice_subscription.invoice)
        .terminated_date_service(subscription, ds)
    end
  end
end
