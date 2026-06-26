# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module AppliedCoupons
    class StatusEnum < Types::BaseEnum
      graphql_name "AppliedCouponStatusEnum"

      AppliedCoupon::STATUSES.each do |type|
        value type
      end
    end
  end
end
