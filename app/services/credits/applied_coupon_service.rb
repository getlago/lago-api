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

      new_credit = Credit.create!(
        invoice: invoice,
        applied_coupon: applied_coupon,
        amount_cents: compute_amount,
        amount_currency: applied_coupon.amount_currency,
      )

      result.credit = new_credit
      result
    rescue ActriveRecord::RecordInvalid => e
      result.fail_with_validations!(e.record)
    end

    private

    attr_accessor :invoice, :applied_coupon

    delegate :coupon, to: :applied_coupon

    def already_applied?
      invoice.credits.where(applied_coupon_id: applied_coupon.id).exists?
    end

    def compute_amount
      return invoice.amount_cents if applied_coupon.amount_cents > invoice.amount_cents

      applied_coupon.amount_cents
    end
  end
end
