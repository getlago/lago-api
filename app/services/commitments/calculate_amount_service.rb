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

      service = Commitments::HelperService.new(commitment:, invoice_subscription:, current_usage: false)
      service_result = service.proration_coefficient

      Money.from_cents(
        commitment.amount_cents * service_result.proration_coefficient,
        commitment.plan.amount_currency,
      ).cents
    end
  end
end
