# frozen_string_literal: true

class RatePhase < ApplicationRecord
  include PaperTrailTraceable
  include Discard::Model

  self.discard_column = :deleted_at

  belongs_to :organization
  belongs_to :plan_rate_card, optional: true
  belongs_to :subscription_rate_card, optional: true

  validates :position, presence: true, numericality: {greater_than: 0}

  validate :validate_exactly_one_parent

  default_scope -> { kept }

  private

  def validate_exactly_one_parent
    has_plan_parent = plan_rate_card_id.present? || plan_rate_card.present?
    has_sub_parent = subscription_rate_card_id.present? || subscription_rate_card.present?
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
#  plan_rate_card_id         :uuid
#  rate_override_id             :uuid
#  subscription_rate_card_id :uuid
#
# Indexes
#
#  index_rate_phases_on_deleted_at                         (deleted_at)
#  index_rate_phases_on_organization_id                    (organization_id)
#  index_rate_phases_on_plan_rate_card_id               (plan_rate_card_id)
#  index_rate_phases_on_plan_rate_card_id_and_position  (plan_rate_card_id,position) UNIQUE WHERE ((plan_rate_card_id IS NOT NULL) AND (deleted_at IS NULL))
#  index_rate_phases_on_sub_product_item_id_and_position   (subscription_rate_card_id,position) UNIQUE WHERE ((subscription_rate_card_id IS NOT NULL) AND (deleted_at IS NULL))
#  index_rate_phases_on_subscription_rate_card_id       (subscription_rate_card_id)
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (plan_rate_card_id => plan_rate_cards.id)
#  fk_rails_...  (subscription_rate_card_id => subscription_rate_cards.id)
#
