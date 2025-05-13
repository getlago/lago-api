# frozen_string_literal: true

module Coupons
  class VoidAndRestoreAppliedCouponService < BaseService
    def initialize(credit:)
      @credit = credit
      @applied_coupon = credit.applied_coupon
      super
    end

    def call
      return result.not_found_failure!(resource: "applied_coupon") if applied_coupon.nil?
      return result.not_allowed_failure!(code: "already_voided") if applied_coupon.voided?
      return result if unlimited_usage?
      return result if expired?

      applied_coupon.with_lock do
        applied_coupon.mark_as_voided!
        result.restored_applied_coupon = create_new_applied_coupon!
      end
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :credit, :applied_coupon

    def unlimited_usage?
      applied_coupon.frequency.to_sym == :forever
    end

    def expired?
      applied_coupon.coupon.expiration_at&.< Time.current
    end

    def create_new_applied_coupon!
      # Prepare parameters for the new applied coupon
      params = {
        amount_cents: applied_coupon.amount_cents,
        amount_currency: applied_coupon.amount_currency,
        percentage_rate: applied_coupon.percentage_rate,
        frequency: applied_coupon.frequency,
        frequency_duration: applied_coupon.frequency_duration
      }

      # For recurring coupons, calculate the correct remaining usage count
      if applied_coupon.recurring?
        # Count active credits associated with this coupon
        active_credits_count = count_active_credits

        # Calculate remaining usage based on original frequency duration minus active credits
        # This ensures the correct count regardless of the order invoices are voided
        params[:frequency_duration_remaining] = applied_coupon.frequency_duration - active_credits_count
      end

      # Use the existing service to create a new applied coupon
      create_result = AppliedCoupons::CreateService.call(
        customer: applied_coupon.customer,
        coupon: applied_coupon.coupon,
        params: params
      )

      # Handle potential errors
      create_result.raise_if_error!

      # Return the newly created applied coupon
      create_result.applied_coupon
    end

    # Count the number of active (non-voided) credits associated with this coupon
    def count_active_credits
      # Get all credits for this coupon excluding the current one being voided
      Credit.joins(:invoice)
        .where(applied_coupon_id: applied_coupon.id)
        .where.not(id: credit.id)
        .where.not(invoices: {status: :voided})
        .count
    end
  end
end
