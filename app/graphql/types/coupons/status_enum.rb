# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module Coupons
    class StatusEnum < Types::BaseEnum
      graphql_name "CouponStatusEnum"

      Coupon::STATUSES.each do |type|
        value type
      end
    end
  end
end
