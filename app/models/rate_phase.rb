# frozen_string_literal: true

class RatePhase < ApplicationRecord
  include PaperTrailTraceable
  include Discard::Model

  self.discard_column = :deleted_at

  belongs_to :organization
  belongs_to :plan_rate_card, optional: true
  belongs_to :contract_rate_card, optional: true
  belongs_to :rate_override, optional: true

  validates :code, presence: true
  validates :code,
    uniqueness: {scope: :plan_rate_card_id, conditions: -> { where(deleted_at: nil) }},
    if: :plan_rate_card_id?
  validates :code,
    uniqueness: {scope: :contract_rate_card_id, conditions: -> { where(deleted_at: nil) }},
    if: :contract_rate_card_id?
  validates :position, presence: true, numericality: {greater_than: 0}
  # nil = indefinite (terminal) phase; a zero-cycle phase would never bill.
  validates :billing_interval_cycle_count, numericality: {greater_than: 0}, allow_nil: true
  validates :rate_override_id, uniqueness: {conditions: -> { where(deleted_at: nil) }}, allow_nil: true

  validate :validate_exactly_one_parent

  default_scope -> { kept }

  private

  def validate_exactly_one_parent
    has_plan_parent = plan_rate_card_id.present? || plan_rate_card.present?
    has_contract_parent = contract_rate_card_id.present? || contract_rate_card.present?
    return if has_plan_parent ^ has_contract_parent

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
#  code                         :string           not null
#  deleted_at                   :datetime
#  name                         :string
#  position                     :integer          not null
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#  contract_rate_card_id        :uuid
#  organization_id              :uuid             not null
#  plan_rate_card_id            :uuid
#  rate_override_id             :uuid
#
# Indexes
#
#  index_rate_phases_on_contract_rate_card_id               (contract_rate_card_id)
#  index_rate_phases_on_contract_rate_card_id_and_code      (contract_rate_card_id,code) UNIQUE WHERE ((contract_rate_card_id IS NOT NULL) AND (deleted_at IS NULL))
#  index_rate_phases_on_contract_rate_card_id_and_position  (contract_rate_card_id,position) UNIQUE WHERE ((contract_rate_card_id IS NOT NULL) AND (deleted_at IS NULL))
#  index_rate_phases_on_deleted_at                          (deleted_at)
#  index_rate_phases_on_organization_id                     (organization_id)
#  index_rate_phases_on_plan_rate_card_id                   (plan_rate_card_id)
#  index_rate_phases_on_plan_rate_card_id_and_code          (plan_rate_card_id,code) UNIQUE WHERE ((plan_rate_card_id IS NOT NULL) AND (deleted_at IS NULL))
#  index_rate_phases_on_plan_rate_card_id_and_position      (plan_rate_card_id,position) UNIQUE WHERE ((plan_rate_card_id IS NOT NULL) AND (deleted_at IS NULL))
#  index_rate_phases_on_rate_override_id                    (rate_override_id) UNIQUE WHERE ((rate_override_id IS NOT NULL) AND (deleted_at IS NULL))
#
# Foreign Keys
#
#  fk_rails_...  (contract_rate_card_id => contract_rate_cards.id)
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (plan_rate_card_id => plan_rate_cards.id)
#  fk_rails_...  (rate_override_id => rate_overrides.id)
#
