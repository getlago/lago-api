# frozen_string_literal: true

module Coupons
  class VoidAndRestoreAppliedCouponService < BaseService
    def initialize(credit:)
      @credit = credit
      @applied_coupon = credit.applied_coupon
      super
    end

    def call
      raise result.not_found_failure!(resource: "applied_coupon") if applied_coupon.nil?
      next result if unlimited_usage?

      applied_coupon.with_lock do
        raise result.not_allowed_failure!(code: "already_voided") if applied_coupon.voided?
        next result if expired?
        applied_coupon.mark_as_voided!
        result.restored_applied_coupon = create_new_applied_coupon!
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :credit, :applied_coupon

    def create_new_applied_coupon!
      AppliedCoupon.create!(
        coupon: applied_coupon.coupon,
        customer: applied_coupon.customer,
        amount_cents: applied_coupon.amount_cents,
        amount_currency: applied_coupon.amount_currency,
        percentage_rate: applied_coupon.percentage_rate,
        frequency: applied_coupon.frequency,
        frequency_duration: applied_coupon.frequency_duration,
        frequency_duration_remaining: applied_coupon.frequency_duration_remaining,
        status: :active
      )
    end

    def unlimited_usage?
      applied_coupon.frequency.to_sym == :forever
    end

    def expired?
      applied_coupon.terminated? || (applied_coupon.terminated_at&.< Time.current)
    end
  end
end
