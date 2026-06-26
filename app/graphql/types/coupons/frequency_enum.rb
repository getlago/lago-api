# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module Coupons
    class FrequencyEnum < Types::BaseEnum
      graphql_name "CouponFrequency"

      Coupon::FREQUENCIES.each do |type|
        value type
      end
    end
  end
end
