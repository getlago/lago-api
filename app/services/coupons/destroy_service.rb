# frozen_string_literal: true

module Coupons
  class DestroyService < BaseService
    def destroy(id)
      coupon = result.user.coupons.find_by(id: id)
      return result.fail!('not_found') unless coupon

      unless coupon.deletable?
        return result.fail!(
          'forbidden',
          'Coupon is attached to an active customer',
        )
      end

      coupon.destroy!

      result.coupon = coupon
      result
    end

    def destroy_from_api(organization:, code:)
      coupon = organization.coupons.find_by(code: code)
      return result.fail!('not_found', 'coupon does not exist') unless coupon

      unless coupon.deletable?
        return result.fail!(
          'forbidden',
          'coupon is attached to an active customer',
        )
      end

      coupon.destroy!

      result.coupon = coupon
      result
    end

    def terminate(id)
      coupon = result.user.coupons.find_by(id: id)
      return result.fail!('not_found') unless coupon

      coupon.mark_as_terminated! unless coupon.terminated?

      result.coupon = coupon
      result
    rescue ActiveRecord::RecordInvalid => e
      result.fail_with_validations!(e.record)
    end
  end
end
