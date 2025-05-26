# frozen_string_literal: true

module AppliedCoupons
  class RecreditService < BaseService
    def initialize(credit:)
      @credit = credit
      @applied_coupon = credit.applied_coupon
      @invoice = credit.invoice

      super
    end

    def call
      return result.not_found_failure!(resource: "applied_coupon") if applied_coupon.nil?

      result.applied_coupon = applied_coupon

      # For recurring coupons, increment the frequency_duration_remaining
      if applied_coupon.recurring?
        applied_coupon.frequency_duration_remaining += 1
        applied_coupon.save!
      end

      # If the coupon was terminated and this was the last credit that caused it to be terminated,
      # reactivate the coupon
      if applied_coupon.terminated? && should_reactivate_coupon?
        applied_coupon.status = :active
        applied_coupon.terminated_at = nil
        applied_coupon.save!
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :credit, :applied_coupon, :invoice

    def should_reactivate_coupon?
      # Forever coupons don't need to be reactivated as they don't get terminated due to usage
      return false if applied_coupon.forever?

      # Only reactivate coupons that were terminated due to usage
      # For once coupons
      if applied_coupon.once?
        # If the coupon is percentage-based, it's always terminated after one use
        # so we can safely reactivate it
        return true if applied_coupon.coupon.percentage?

        # For fixed amount coupons, check if this credit would make the coupon usable again
        credit_amount = credit.amount_cents
        remaining_amount_without_this_credit = calculate_remaining_amount_without_this_credit
        
        # If adding this credit back would make the remaining amount positive, reactivate
        return remaining_amount_without_this_credit + credit_amount > 0
      else
        # For recurring coupons, check if incrementing the frequency_duration_remaining would make it positive
        return applied_coupon.frequency_duration_remaining + 1 > 0
      end
    end

    def calculate_remaining_amount_without_this_credit
      # Calculate remaining amount excluding this specific credit
      # Also exclude credits from voided invoices
      total_credits_amount = applied_coupon.credits
        .joins(:invoice)
        .where.not(id: credit.id)
        .where.not(invoices: { status: :voided })
        .sum(:amount_cents)
      
      applied_coupon.amount_cents - total_credits_amount
    end
  end
end
