# frozen_string_literal: true

module Coupons
  class TerminateService < BaseService
    def terminate(id)
      coupon = result.user.coupons.find_by(id: id)
      return result.fail!('not_found') unless coupon

      coupon.mark_as_terminated! unless coupon.terminated?

      result.coupon = coupon
      result
    rescue ActiveRecord::RecordInvalid => e
      result.fail_with_validations!(e.record)
    end

    def terminate_all_expired
      coupons = Coupon
        .active
        .time_limit
        .expired

      coupons.find_each do |coupon|
        coupon.mark_as_terminated!

        coupon.applied_coupons.active.find_each(&:mark_as_terminated!)
      end
    end
  end
end
