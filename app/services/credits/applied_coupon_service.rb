# frozen_string_literal: true

module Credits
  class AppliedCouponService < BaseService
    def initialize(invoice:, applied_coupon:)
      @invoice = invoice
      @applied_coupon = applied_coupon

      super(nil)
    end

    def create
      return result if already_applied?

      credit_amount = compute_amount

      new_credit = Credit.create!(
        invoice: invoice,
        applied_coupon: applied_coupon,
        amount_cents: credit_amount,
        amount_currency: applied_coupon.amount_currency,
      )

      applied_coupon.mark_as_terminated! if credit_amount >= remaining_amount

      result.credit = new_credit
      result
    rescue ActiveRecord::RecordInvalid => e
      result.fail_with_validations!(e.record)
    end

    private

    attr_accessor :invoice, :applied_coupon

    delegate :coupon, to: :applied_coupon

    def already_applied?
      invoice.credits.where(applied_coupon_id: applied_coupon.id).exists?
    end

    def compute_amount
      return invoice.amount_cents if remaining_amount > invoice.amount_cents

      remaining_amount
    end

    def remaining_amount
      return @remaining_amount if @remaining_amount

      already_applied_amount = applied_coupon.credits.sum(:amount_cents)
      @remaining_amount = applied_coupon.amount_cents - already_applied_amount
    end
  end
end
