# frozen_string_literal: true

class PlanProduct < ApplicationRecord
  include PaperTrailTraceable
  include Discard::Model

  self.discard_column = :deleted_at

  belongs_to :organization
  belongs_to :plan
  belongs_to :product

  validates :product_id, uniqueness: {scope: :plan_id, conditions: -> { where(deleted_at: nil) }}

  default_scope -> { kept }
end

# == Schema Information
#
# Table name: plan_products
# Database name: primary
#
#  id              :uuid             not null, primary key
#  deleted_at      :datetime
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  organization_id :uuid             not null
#  plan_id         :uuid             not null
#  product_id      :uuid             not null
#
# Indexes
#
#  index_plan_products_on_deleted_at              (deleted_at)
#  index_plan_products_on_organization_id         (organization_id)
#  index_plan_products_on_plan_id                 (plan_id)
#  index_plan_products_on_plan_id_and_product_id  (plan_id,product_id) UNIQUE WHERE (deleted_at IS NULL)
#  index_plan_products_on_product_id              (product_id)
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (plan_id => plans.id)
#  fk_rails_...  (product_id => products.id)
#
