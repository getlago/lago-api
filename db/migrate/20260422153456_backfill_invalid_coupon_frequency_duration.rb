# frozen_string_literal: true

class BackfillInvalidCouponFrequencyDuration < ActiveRecord::Migration[8.0]
  def up
    backfill_applied_coupon_remaining
    backfill_invalid_applied_coupons
    backfill_invalid_coupons
  end

  def down
    # No-op: terminated records and backfilled values must not be reversed
  end

  private

  def backfill_applied_coupon_remaining
    AppliedCoupon
      .where(frequency: AppliedCoupon.frequencies[:recurring], frequency_duration_remaining: nil)
      .where("frequency_duration > 0")
      .update_all("frequency_duration_remaining = frequency_duration, updated_at = NOW()") # rubocop:disable Rails/SkipsModelValidations
  end

  def backfill_invalid_applied_coupons
    AppliedCoupon
      .where(frequency: AppliedCoupon.frequencies[:recurring])
      .where(frequency_duration: nil)
      .update_all(frequency_duration: 1, frequency_duration_remaining: 1, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations

    AppliedCoupon
      .where(frequency: AppliedCoupon.frequencies[:recurring])
      .where("frequency_duration < 0")
      .update_all(frequency_duration: 0, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  def backfill_invalid_coupons
    Coupon
      .where(frequency: Coupon.frequencies[:recurring], status: Coupon.statuses[:active])
      .where("frequency_duration IS NULL")
      .update_all(frequency_duration: 1, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations

    Coupon
      .where(frequency: Coupon.frequencies[:recurring], status: Coupon.statuses[:active])
      .where("frequency_duration < 0")
      .update_all(frequency_duration: 0, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end
end
