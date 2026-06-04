# frozen_string_literal: true

class RatePhase < ApplicationRecord
  include PaperTrailTraceable
  include Discard::Model

  self.discard_column = :deleted_at

  belongs_to :organization
  belongs_to :plan_product_item, optional: true
  belongs_to :subscription_product_item, optional: true

  validates :position, presence: true, numericality: {greater_than: 0}

  validate :validate_exactly_one_parent

  default_scope -> { kept }

  private

  def validate_exactly_one_parent
    has_plan_parent = plan_product_item_id.present? || plan_product_item.present?
    has_sub_parent = subscription_product_item_id.present? || subscription_product_item.present?
    return if has_plan_parent ^ has_sub_parent

    errors.add(:base, :exactly_one_parent_required)
  end
end

# == Schema Information
#
# Table name: rate_phases
# Database name: primary
#
#  id                           :uuid             not null, primary key
#  billing_interval_cycle_count :integer
#  deleted_at                   :datetime
#  position                     :integer          not null
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#  organization_id              :uuid             not null
#  plan_product_item_id         :uuid
#  rate_override_id             :uuid
#  subscription_product_item_id :uuid
#
# Indexes
#
#  index_rate_phases_on_deleted_at                         (deleted_at)
#  index_rate_phases_on_organization_id                    (organization_id)
#  index_rate_phases_on_plan_product_item_id               (plan_product_item_id)
#  index_rate_phases_on_plan_product_item_id_and_position  (plan_product_item_id,position) UNIQUE WHERE ((plan_product_item_id IS NOT NULL) AND (deleted_at IS NULL))
#  index_rate_phases_on_sub_product_item_id_and_position   (subscription_product_item_id,position) UNIQUE WHERE ((subscription_product_item_id IS NOT NULL) AND (deleted_at IS NULL))
#  index_rate_phases_on_subscription_product_item_id       (subscription_product_item_id)
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (plan_product_item_id => plan_product_items.id)
#  fk_rails_...  (subscription_product_item_id => subscription_product_items.id)
#
