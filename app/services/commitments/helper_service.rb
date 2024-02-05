# frozen_string_literal: true

module Commitments
  class HelperService < BaseService
    def initialize(commitment:, invoice_subscription:, current_usage: false)
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

    attr_reader :commitment, :invoice_subscription, :current_usage

    delegate :subscription, to: :invoice_subscription

    def calculate_proration_coefficient
      all_invoice_subscriptions = subscription
        .invoice_subscriptions
        .where(invoice_id: fetch_period_invoice_ids)
        .order(
          Arel.sql(
            ActiveRecord::Base.sanitize_sql_for_conditions(
              'COALESCE(invoice_subscriptions.to_datetime, invoice_subscriptions.created_at) ASC',
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
      # TODO: in case if it's billed monthly, yearly plan
      # we need to select all the invoice_subscriptions for the whole year not just
      # one invoice_subscription (fees table)
      plan = invoice_subscription.subscription.plan

      if !invoice_subscription.subscription.plan.yearly? || !plan.bill_charges_monthly?
        return [invoice_subscription.invoice_id]
      end

      subscription
        .invoice_subscriptions
        .where(
          'charges_from_datetime >= ? AND charges_to_datetime <= ?',
          dates_service.previous_beginning_of_period,
          dates_service.end_of_period,
        )
        .pluck(:invoice_id)
    end

    def dates_service
      Subscriptions::DatesService.new_instance(subscription, invoice_subscription.timestamp, current_usage:)
    end
  end
end
