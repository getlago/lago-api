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
  end
end
