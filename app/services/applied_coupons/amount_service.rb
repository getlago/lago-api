# frozen_string_literal: true

module AppliedCoupons
  class AmountService < BaseService
    Result = BaseResult[:amount]

    def initialize(applied_coupon:, base_amount_cents:, invoice:)
      @applied_coupon = applied_coupon
      @base_amount_cents = base_amount_cents
      @invoice = invoice

      super
    end

    def call
      return result.not_found_failure!(resource: "applied_coupon") unless applied_coupon

      result.amount = compute_amount
      result
    end

    private

    attr_reader :applied_coupon, :base_amount_cents, :invoice

    def compute_amount
      if applied_coupon.coupon.percentage?
        discounted_value = base_amount_cents * applied_coupon.percentage_rate.fdiv(100)

        return (discounted_value >= base_amount_cents) ? base_amount_cents : discounted_value.round
      end

      remaining_amount = if applied_coupon.once?
        applied_coupon.remaining_amount
      else
        applied_coupon.remaining_amount_in_billing_period(invoice)
      end

      [remaining_amount, base_amount_cents].min
    end
  end
end
