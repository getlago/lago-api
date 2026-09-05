# frozen_string_literal: true

class PlanRateCard < ApplicationRecord
  include PaperTrailTraceable
  include Discard::Model

  self.discard_column = :deleted_at

  belongs_to :organization
  belongs_to :plan, optional: true
  belongs_to :catalog_plan, optional: true
  belongs_to :rate_card

  has_one :product, through: :rate_card

  has_many :rate_phases, -> { order(:position) }

  validates :rate_card_id, uniqueness: {scope: %i[plan_id catalog_plan_id], conditions: -> { where(deleted_at: nil) }}
  validates :units, numericality: {greater_than_or_equal_to: 0}, allow_nil: true

  validate :exactly_one_plan

  default_scope -> { kept }

  def edit_error_code
    "plan_locked" if plan&.attached_to_subscriptions?
  end

  private

  # A rate card is applied to exactly one plan, legacy or catalog. The
  # association is checked, not the id, so an unsaved parent still counts.
  def exactly_one_plan
    return if plan.present? ^ catalog_plan.present?

    errors.add(:base, :exactly_one_plan_required)
  end
end

# == Schema Information
#
# Table name: plan_rate_cards
# Database name: primary
#
#  id              :uuid             not null, primary key
#  deleted_at      :datetime
#  units           :decimal(, )
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  catalog_plan_id :uuid
#  organization_id :uuid             not null
#  plan_id         :uuid
#  rate_card_id    :uuid             not null
#
# Indexes
#
#  index_plan_rate_cards_on_catalog_plan_id_and_rate_card_id  (catalog_plan_id,rate_card_id) UNIQUE WHERE (deleted_at IS NULL)
#  index_plan_rate_cards_on_deleted_at                        (deleted_at)
#  index_plan_rate_cards_on_organization_id                   (organization_id)
#  index_plan_rate_cards_on_plan_id                           (plan_id)
#  index_plan_rate_cards_on_plan_id_and_rate_card_id          (plan_id,rate_card_id) UNIQUE WHERE (deleted_at IS NULL)
#  index_plan_rate_cards_on_rate_card_id                      (rate_card_id)
#
# Foreign Keys
#
#  fk_rails_...  (catalog_plan_id => catalog_plans.id)
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (plan_id => plans.id)
#  fk_rails_...  (rate_card_id => rate_cards.id)
#
