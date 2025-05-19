# frozen_string_literal: true

module AppliedCoupons
  class VoidAndRestoreService < BaseService
    def initialize(credit:)
      @credit = credit
      @applied_coupon = credit.applied_coupon
      super
    end

    def call
      return result.not_found_failure!(resource: "applied_coupon") if applied_coupon.nil?
      return result.not_allowed_failure!(code: "already_voided") if applied_coupon.voided?
      return result if unlimited_usage? || expired?

      applied_coupon.with_lock do
        if applied_coupon.recurring?
          result.restored_applied_coupon = restore_recurring_usage!
        else
          applied_coupon.mark_as_voided!
          result.restored_applied_coupon = create_new_applied_coupon!
        end
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

    def restore_recurring_usage!
      applied_coupon.update!(
        frequency_duration_remaining: [
          (applied_coupon.frequency_duration_remaining || 0) + 1,
          applied_coupon.frequency_duration
        ].min
      )
      applied_coupon
    end

    def create_new_applied_coupon!
      params = {
        amount_cents: applied_coupon.amount_cents,
        amount_currency: applied_coupon.amount_currency,
        percentage_rate: applied_coupon.percentage_rate,
        frequency: applied_coupon.frequency,
        frequency_duration: applied_coupon.frequency_duration
      }

      create_result = AppliedCoupons::CreateService.call(
        customer: applied_coupon.customer,
        coupon: applied_coupon.coupon,
        params: params
      )

      create_result.raise_if_error!
      create_result.applied_coupon
    end
  end
end