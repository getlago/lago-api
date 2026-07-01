# frozen_string_literal: true

class PlanProductItem < ApplicationRecord
  include PaperTrailTraceable
  include Discard::Model

  self.discard_column = :deleted_at

  belongs_to :organization
  belongs_to :plan
  belongs_to :product_item
  belongs_to :rate_card

  has_many :rate_phases

  validates :rate_card_id, uniqueness: {scope: [:plan_id, :product_item_id], conditions: -> { where(deleted_at: nil) }}

  default_scope -> { kept }
end

# == Schema Information
#
# Table name: plan_product_items
# Database name: primary
#
#  id              :uuid             not null, primary key
#  deleted_at      :datetime
#  units           :decimal(30, 10)
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  organization_id :uuid             not null
#  plan_id         :uuid             not null
#  product_item_id :uuid             not null
#  rate_card_id    :uuid             not null
#
# Indexes
#
#  index_plan_product_items_on_deleted_at               (deleted_at)
#  index_plan_product_items_on_organization_id          (organization_id)
#  index_plan_product_items_on_plan_id                  (plan_id)
#  index_plan_product_items_on_plan_item_and_rate_card  (plan_id,product_item_id,rate_card_id) UNIQUE WHERE (deleted_at IS NULL)
#  index_plan_product_items_on_product_item_id          (product_item_id)
#  index_plan_product_items_on_rate_card_id             (rate_card_id)
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (plan_id => plans.id)
#  fk_rails_...  (product_item_id => product_items.id)
#  fk_rails_...  (rate_card_id => rate_cards.id)
#
