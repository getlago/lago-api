# frozen_string_literal: true

module Coupons
  class VoidAndRestoreAppliedCouponService < BaseService
    def initialize(applied_coupon:)
      @applied_coupon = applied_coupon
      super()
    end

    def call
      return result.not_found_failure!(resource: "applied_coupon") if applied_coupon.nil?

      ActiveRecord::Base.transaction do
        applied_coupon.mark_as_voided!

        if should_restore_usage?
          result.restored_applied_coupon = create_new_applied_coupon!
        end
      end

      result.success!
    rescue => e
      result.error!(message: "Failed to void and restore coupon: #{e.message}")
    end

    private

    attr_reader :applied_coupon

    def should_restore_usage?
      applied_coupon.coupon.reusable? &&
        applied_coupon.remaining_amount.positive?
    end

    def create_new_applied_coupon!
      AppliedCoupon.create!(
        coupon: applied_coupon.coupon,
        customer: applied_coupon.customer,
        amount_cents: applied_coupon.remaining_amount,
        amount_currency: applied_coupon.amount_currency,
        percentage_rate: applied_coupon.percentage_rate,
        frequency: applied_coupon.frequency,
        frequency_duration: applied_coupon.frequency_duration,
        frequency_duration_remaining: applied_coupon.frequency_duration_remaining,
        status: :active
      )
    end
  end
end
