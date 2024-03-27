# frozen_string_literal: true

module Types
  module Coupons
    class CouponTypeEnum < Types::BaseEnum
      graphql_name "CouponTypeEnum"

      Coupon::COUPON_TYPES.each do |type|
        value type
      end
    end
  end
end
