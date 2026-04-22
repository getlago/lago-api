# frozen_string_literal: true

class BackfillInvalidCouponFrequencyDuration < ActiveRecord::Migration[8.0]
  def up
    backfill_applied_coupon_remaining
    terminate_invalid_applied_coupons
    terminate_invalid_coupons
  end

  def down
    # No-op: terminated records and backfilled values must not be reversed
  end

  private

  def backfill_applied_coupon_remaining
    AppliedCoupon
      .where(frequency: AppliedCoupon.frequencies[:recurring], frequency_duration_remaining: nil)
      .where("frequency_duration > 0")
      .update_all("frequency_duration_remaining = frequency_duration, updated_at = NOW()")
  end

  def terminate_invalid_applied_coupons
    AppliedCoupon
      .where(frequency: AppliedCoupon.frequencies[:recurring], status: AppliedCoupon.statuses[:active])
      .where(
        "frequency_duration IS NULL OR frequency_duration <= 0 OR " \
        "frequency_duration_remaining IS NULL OR frequency_duration_remaining <= 0"
      )
      .update_all(
        status: AppliedCoupon.statuses[:terminated],
        terminated_at: Time.current,
        updated_at: Time.current
      )
  end

  def terminate_invalid_coupons
    Coupon
      .where(frequency: Coupon.frequencies[:recurring], status: Coupon.statuses[:active])
      .where("frequency_duration IS NULL OR frequency_duration <= 0")
      .update_all(
        status: Coupon.statuses[:terminated],
        terminated_at: Time.current,
        updated_at: Time.current
      )
  end
end
