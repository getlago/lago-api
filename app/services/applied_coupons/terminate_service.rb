# frozen_string_literal: true

module AppliedCoupons
  class TerminateService < BaseService
    def terminate(id)
      applied_coupon = AppliedCoupon
        .joins(coupon: :organization)
        .where(organizations: { id: result.user.organization_ids })
        .find_by(id: id)

      return result.not_found_failure!(resource: 'applied_coupon') unless applied_coupon

      applied_coupon.mark_as_terminated! unless applied_coupon.terminated?

      result.applied_coupon = applied_coupon
      result
    rescue ActiveRecord::RecordInvalid => e
      result.fail_with_validations!(e.record)
    end
  end
end
