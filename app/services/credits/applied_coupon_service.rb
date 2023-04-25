# frozen_string_literal: true

module Credits
  class AppliedCouponService < BaseService
    def initialize(invoice:, applied_coupon:, base_amount_cents:)
      @invoice = invoice
      @applied_coupon = applied_coupon
      # base_amount_cents represents maximum value that can be credited. It is either equal to invoice
      # total_amount_cents or sum of the fees related to some plan (for coupons with plan limitations)
      @base_amount_cents = base_amount_cents

      super(nil)
    end

    def create
      return result if already_applied?

      credit_amount = compute_amount

      new_credit = Credit.create!(
        invoice:,
        applied_coupon:,
        amount_cents: credit_amount,
        amount_currency: invoice.currency,
        before_vat: false, # NOTE: will turn to true with invoice v3
      )

      applied_coupon.frequency_duration_remaining -= 1 if applied_coupon.recurring?
      if should_terminate_applied_coupon?(credit_amount)
        applied_coupon.mark_as_terminated!
      elsif applied_coupon.recurring?
        applied_coupon.save!
      end

      result.credit = new_credit
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_accessor :invoice, :applied_coupon, :base_amount_cents

    delegate :coupon, to: :applied_coupon

    def already_applied?
      invoice.credits.where(applied_coupon_id: applied_coupon.id).exists?
    end

    def compute_amount
      if applied_coupon.coupon.percentage?
        discounted_value = base_amount_cents * applied_coupon.percentage_rate.fdiv(100)

        return (discounted_value >= base_amount_cents) ? base_amount_cents : discounted_value.round
      end

      if applied_coupon.recurring? || applied_coupon.forever?
        return base_amount_cents if applied_coupon.amount_cents > base_amount_cents

        applied_coupon.amount_cents
      else
        return base_amount_cents if remaining_amount > base_amount_cents

        remaining_amount
      end
    end

    def remaining_amount
      return @remaining_amount if @remaining_amount

      already_applied_amount = applied_coupon.credits.sum(:amount_cents)
      @remaining_amount = applied_coupon.amount_cents - already_applied_amount
    end

    def should_terminate_applied_coupon?(credit_amount)
      return false if applied_coupon.forever?

      if applied_coupon.once?
        applied_coupon.coupon.percentage? || credit_amount >= remaining_amount
      else
        applied_coupon.frequency_duration_remaining <= 0
      end
    end
  end
end
