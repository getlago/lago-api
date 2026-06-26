# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module Coupons
    class ExpirationEnum < Types::BaseEnum
      graphql_name "CouponExpiration"

      Coupon::EXPIRATION_TYPES.each do |type|
        value type
      end
    end
  end
end
