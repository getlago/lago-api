# frozen_string_literal: true

class CouponPlan < ApplicationRecord
  belongs_to :coupon
  belongs_to :plan
end
