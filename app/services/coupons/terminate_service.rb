# frozen_string_literal: true

module Coupons
  class TerminateService < BaseService
    def terminate(id)
      coupon = result.user.coupons.find_by(id: id)
      return result.not_found_failure!(code: 'coupon_not_found') unless coupon

      coupon.mark_as_terminated! unless coupon.terminated?

      result.coupon = coupon
      result
    rescue ActiveRecord::RecordInvalid => e
      result.fail_with_validations!(e.record)
    end

    def terminate_all_expired
      Coupon
        .active
        .time_limit
        .expired
        .find_each(&:mark_as_terminated!)
    end
  end
end
