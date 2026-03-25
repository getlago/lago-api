# frozen_string_literal: true

class PlanProductItem < ApplicationRecord
  include PaperTrailTraceable
  include Discard::Model

  self.discard_column = :deleted_at

  belongs_to :organization
  belongs_to :plan, -> { with_discarded }
  belongs_to :product_item, -> { with_discarded }

  # has_many :rate_schedules

  validates :product_item_id,
    uniqueness: {conditions: -> { where(deleted_at: nil) }, scope: :plan_id}

  default_scope -> { kept }
end

# == Schema Information
#
# Table name: plan_product_items
# Database name: primary
#
#  id              :uuid             not null, primary key
#  deleted_at      :datetime
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  organization_id :uuid             not null
#  plan_id         :uuid             not null
#  product_item_id :uuid             not null
#
# Indexes
#
#  idx_plan_product_items_on_plan_and_product_item  (plan_id,product_item_id) UNIQUE WHERE (deleted_at IS NULL)
#  index_plan_product_items_on_deleted_at           (deleted_at)
#  index_plan_product_items_on_organization_id      (organization_id)
#  index_plan_product_items_on_plan_id              (plan_id)
#  index_plan_product_items_on_product_item_id      (product_item_id)
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (plan_id => plans.id)
#  fk_rails_...  (product_item_id => product_items.id)
#
