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

# == Schema Information
#
# Table name: coupon_targets
#
#  id                 :uuid             not null, primary key
#  coupon_id          :uuid             not null
#  plan_id            :uuid
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  deleted_at         :datetime
#  billable_metric_id :uuid
#
# Indexes
#
#  index_coupon_targets_on_billable_metric_id  (billable_metric_id)
#  index_coupon_targets_on_coupon_id           (coupon_id)
#  index_coupon_targets_on_deleted_at          (deleted_at)
#  index_coupon_targets_on_plan_id             (plan_id)
#
