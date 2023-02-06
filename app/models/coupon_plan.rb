# frozen_string_literal: true

class CouponPlan < ApplicationRecord
  include Discard::Model
  self.discard_column = :deleted_at

  belongs_to :coupon
  belongs_to :plan

  default_scope -> { kept }
end
