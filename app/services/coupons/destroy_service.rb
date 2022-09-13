# frozen_string_literal: true

module Coupons
  class DestroyService < BaseService
    def destroy(id)
      coupon = result.user.coupons.find_by(id: id)
      return result.not_found_failure!(resource: 'coupon') unless coupon
      return result.not_allowed_failure!(code: 'attached_to_an_active_customer') unless coupon.deletable?

      coupon.destroy!

      result.coupon = coupon
      result
    end

    def destroy_from_api(organization:, code:)
      coupon = organization.coupons.find_by(code: code)
      return result.not_found_failure!(resource: 'coupon') unless coupon
      return result.not_allowed_failure!(code: 'attached_to_an_active_customer') unless coupon.deletable?

      coupon.destroy!

      result.coupon = coupon
      result
    end

    def terminate(id)
      coupon = result.user.coupons.find_by(id: id)
      return result.not_found_failure!(resource: 'coupon') unless coupon

      coupon.mark_as_terminated! unless coupon.terminated?

      result.coupon = coupon
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end
  end
end
