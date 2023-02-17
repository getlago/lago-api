# frozen_string_literal: true

module AppliedCoupons
  class TerminateService < BaseService
    def initialize(applied_coupon:)
      @applied_coupon = applied_coupon
      super
    end

    def call
      return result.not_found_failure!(resource: 'applied_coupon') unless applied_coupon

      applied_coupon.mark_as_terminated! unless applied_coupon.terminated?

      result.applied_coupon = applied_coupon
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :applied_coupon
  end
end
