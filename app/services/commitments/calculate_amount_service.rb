# frozen_string_literal: true

module Commitments
  class CalculateAmountService < BaseService
    def initialize(commitment:, invoice_subscription:)
      @commitment = commitment
      @invoice_subscription = invoice_subscription

      super
    end

    def call
      result.commitment_amount_cents = commitment_amount_cents
      result
    end

    private

    attr_reader :commitment, :invoice_subscription

    delegate :subscription, to: :invoice_subscription

    def commitment_amount_cents
      return 0 if !commitment || !invoice_subscription || commitment.amount_cents.zero?

      # No proration when subscription is anniversary
      return commitment.amount_cents if subscription.anniversary?

      # Prorate the commitment fee amount in case of calendar subscriptions
      Money.from_cents(commitment.amount_cents * proration_coefficient, commitment.plan.amount_currency).cents
    end

    def proration_coefficient
      days = Utils::DatetimeService.date_diff_with_timezone(
        invoice_subscription.from_datetime,
        invoice_subscription.to_datetime,
        invoice_subscription.from_datetime.time_zone,
      )

      days_total = Utils::DatetimeService.period_total_length_in_days(
        invoice_subscription.from_datetime,
        invoice_subscription.to_datetime,
        commitment.plan.interval,
      )

      days / days_total.to_f
    end
  end
end
