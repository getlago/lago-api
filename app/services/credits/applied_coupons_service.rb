# frozen_string_literal: true

module Credits
  class AppliedCouponsService < BaseService
    def initialize(invoice:)
      @invoice = invoice
      super
    end

    def call
      return result if applied_coupons.blank?
      return result if invoice.fees_amount_cents.zero?

      applied_coupons.each do |applied_coupon|
        break unless invoice.fees_amount_cents&.positive?
        next if applied_coupon.coupon.fixed_amount? && applied_coupon.amount_currency != currency

        fees = if applied_coupon.coupon.limited_billable_metrics?
          billable_metric_related_fees(applied_coupon)
        elsif applied_coupon.coupon.limited_plans?
          plan_related_fees(applied_coupon)
        else
          invoice.fees
        end
        next unless fees.exists?

        base_amount_cents = fees.sum(:amount_cents)
        credit_result = Credits::AppliedCouponService.new(invoice:, applied_coupon:, base_amount_cents:).create
        credit_result.raise_if_error!

        invoice.coupons_amount_cents += credit_result.credit.amount_cents
        invoice.sub_total_vat_excluded_amount_cents -= credit_result.credit.amount_cents
      end

      result.invoice = invoice
      result
    end

    private

    attr_reader :invoice

    delegate :customer, :currency, to: :invoice

    def applied_coupons
      return @applied_coupons if @applied_coupons

      base_scope = customer
        .applied_coupons.active
        .joins(:coupon)
        .order(created_at: :asc)

      with_bm_limit = base_scope.where(coupon: { limited_billable_metrics: true })
      with_plan_limit = base_scope.where(coupon: { limited_plans: true })
      applied_to_all =
        base_scope.where(coupon: { limited_plans: false })
          .where(coupon: { limited_billable_metrics: false })

      @applied_coupons = with_bm_limit + with_plan_limit + applied_to_all
    end

    def plan_related_fees(applied_coupon)
      invoice.fees.joins(subscription: :plan).where(plan: { id: applied_coupon.coupon.coupon_targets.select(:plan_id) })
    end

    def billable_metric_related_fees(applied_coupon)
      invoice
        .fees
        .joins(charge: :billable_metric)
        .where(billable_metric: { id: applied_coupon.coupon.coupon_targets.select(:billable_metric_id) })
    end
  end
end
