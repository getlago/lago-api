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

      result.credits = []

      applied_coupons.each do |applied_coupon|
        break unless invoice.sub_total_excluding_taxes_amount_cents&.positive?

        credit_result = Credits::AppliedCouponService.call(invoice:, applied_coupon:)
        credit_result.raise_if_error!

        result.credits << credit_result.credit
      end

      result.invoice = invoice
      result
    end

    private

    attr_reader :invoice

    delegate :customer, :currency, to: :invoice

    def applied_coupons
      return @applied_coupons if @applied_coupons

      # NOTE: We want to apply first coupons limited to the billable metrics, then the ones limited to the plans
      #       and finally the ones with no limitation
      @applied_coupons = customer
        .applied_coupons.active
        .joins(:coupon)
        .order('coupons.limited_billable_metrics DESC, coupons.limited_plans DESC, applied_coupons.created_at ASC')
    end
  end
end
