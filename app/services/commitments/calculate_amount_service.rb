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

      Money.from_cents(commitment.amount_cents * proration_coefficient, commitment.plan.amount_currency).cents
    end

    def proration_coefficient
      days = Utils::DatetimeService.date_diff_with_timezone(
        invoice_subscription.from_datetime,
        invoice_subscription.to_datetime,
        subscription.customer.applicable_timezone,
      )

      service = Subscriptions::DatesService.new_instance(
        subscription,
        invoice_subscription.timestamp,
      )

      days_total = Utils::DatetimeService.date_diff_with_timezone(
        service.previous_beginning_of_period,
        service.end_of_period,
        subscription.customer.applicable_timezone,
      )

      days / days_total.to_f
    end
  end
end
