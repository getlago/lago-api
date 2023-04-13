# frozen_string_literal: true

class CouponTarget < ApplicationRecord
  include PaperTrailTraceable
  include Discard::Model
  self.discard_column = :deleted_at

  belongs_to :coupon
  belongs_to :plan, optional: true
  belongs_to :billable_metric, optional: true

  default_scope -> { kept }
end
