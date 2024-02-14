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

      service_result = helper_service.proration_coefficient

      Money.from_cents(
        commitment.amount_cents * service_result.proration_coefficient,
        commitment.plan.amount_currency,
      ).cents
    end

    def helper_service
      @helper_service ||= if subscription.plan.pay_in_arrear?
        Commitments::InArrears::HelperService.new(commitment:, invoice_subscription:)
      else
        Commitments::InAdvance::HelperService.new(commitment:, invoice_subscription:)
      end
    end
  end
end
