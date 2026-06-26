# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module Coupons
    class CouponTypeEnum < Types::BaseEnum
      Coupon::COUPON_TYPES.each do |type|
        value type
      end
    end
  end
end
