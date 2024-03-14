# frozen_string_literal: true

module Commitments
  class HelperService < BaseService
    def self.new_instance(commitment:, invoice_subscription:)
      klass = if invoice_subscription.subscription.plan.pay_in_advance?
        Commitments::Minimum::InAdvance::HelperService
      else
        Commitments::Minimum::InArrears::HelperService
      end

      klass.new(commitment:, invoice_subscription:)
    end

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

    def dates_service
      raise NotImplementedError
    end

    private

    attr_reader :commitment, :invoice_subscription

    delegate :subscription, to: :invoice_subscription

    def calculate_proration_coefficient
      all_invoice_subscriptions = subscription
        .invoice_subscriptions
        .where(invoice_id: fetch_period_invoice_ids)
        .where('from_datetime >= ?', dates_service.previous_beginning_of_period)
        .order(
          Arel.sql(
            ActiveRecord::Base.sanitize_sql_for_conditions(
              'COALESCE(invoice_subscriptions.to_datetime, invoice_subscriptions.timestamp) ASC',
            ),
          ),
        )

      days = Utils::DatetimeService.date_diff_with_timezone(
        all_invoice_subscriptions.first.from_datetime,
        subscription.terminated? ? subscription.terminated_at : invoice_subscription.to_datetime,
        subscription.customer.applicable_timezone,
      )

      days_total = Utils::DatetimeService.date_diff_with_timezone(
        dates_service.previous_beginning_of_period,
        dates_service.end_of_period,
        subscription.customer.applicable_timezone,
      )

      days / days_total.to_f
    end
  end
end
