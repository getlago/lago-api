# frozen_string_literal: true

module Credits
  class AppliedCouponsService < BaseService
    def initialize(invoice:)
      @invoice = invoice
      super
    end

    def create
      return result if applied_coupons.blank?

      applied_coupons.each do |applied_coupon|
        break unless invoice.amount_cents&.positive?
        next if applied_coupon.coupon.fixed_amount? && applied_coupon.amount_currency != currency

        base_amount_cents = if applied_coupon.coupon.limited_plans?
          coupon_related_fees = coupon_fees(applied_coupon)
          next unless coupon_related_fees.exists?

          coupon_base_amount_cents(coupon_related_fees:)
        else
          invoice.total_amount_cents
        end

        credit_result = Credits::AppliedCouponService.new(invoice:, applied_coupon:, base_amount_cents:).create
        credit_result.raise_if_error!

        invoice.credit_amount_cents += credit_result.credit.amount_cents
        invoice.total_amount_cents -= credit_result.credit.amount_cents
      end

      result.invoice = invoice
      result
    end

    private

    attr_reader :invoice

    delegate :customer, :currency, to: :invoice

    def applied_coupons
      return @applied_coupons if @applied_coupons

      with_plan_limit = customer.applied_coupons.active.joins(:coupon).where(coupon: { limited_plans: true })
        .order(created_at: :asc)
      applied_to_all = customer.applied_coupons.active.joins(:coupon).where(coupon: { limited_plans: false })
        .order(created_at: :asc)

      @applied_coupons = with_plan_limit + applied_to_all
    end

    def coupon_fees(applied_coupon)
      invoice.fees.joins(subscription: :plan).where(plan: { id: applied_coupon.coupon.coupon_plans.select(:plan_id) })
    end

    def coupon_base_amount_cents(coupon_related_fees:)
      fee_amounts = coupon_related_fees.select(:amount_cents, :vat_amount_cents)
      fees_amount_cents = fee_amounts.sum(&:amount_cents)
      fees_vat_amount_cents = fee_amounts.sum(&:vat_amount_cents)
      total_fees_amount_cents = fees_amount_cents + fees_vat_amount_cents

      # In some cases when credit note is already applied sum from above
      # can be greater than invoice total_amount_cents
      (total_fees_amount_cents > invoice.total_amount_cents) ? invoice.total_amount_cents : total_fees_amount_cents
    end
  end
end
