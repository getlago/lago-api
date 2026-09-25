# frozen_string_literal: true

# A card's calendar period, independent of pricing splits and financial execution.
# ended_at is exclusive and stays at the nominal boundary after early termination.
# reference_started_at preserves the full proration period for an initial stub.
class BillingCycle < ApplicationRecord
  belongs_to :organization
  belongs_to :contract_rate_card, -> { with_discarded }

  has_many :billing_segments

  validates :cycle_index, numericality: {only_integer: true, greater_than_or_equal_to: 0}
  validates :started_at, :ended_at, :reference_started_at, :timezone, presence: true
  validates :timezone, timezone: true

  validate :validate_period_bounds
  validate :validate_organization

  private

  def validate_period_bounds
    if started_at && ended_at && started_at >= ended_at
      errors.add(:ended_at, "must be after started_at (the end is exclusive)")
    end

    if reference_started_at && started_at && reference_started_at > started_at
      errors.add(:reference_started_at, "must be before or equal to started_at")
    end
  end

  def validate_organization
    if contract_rate_card && organization_id != contract_rate_card.organization_id
      errors.add(:organization_id, "must match the contract rate card's organization")
    end
  end
end

# == Schema Information
#
# Table name: billing_cycles
# Database name: primary
#
#  id                    :uuid             not null, primary key
#  cycle_index           :integer          not null
#  ended_at              :datetime         not null
#  reference_started_at  :datetime         not null
#  started_at            :datetime         not null
#  timezone              :string           not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  contract_rate_card_id :uuid             not null
#  organization_id       :uuid             not null
#
# Indexes
#
#  index_billing_cycles_on_contract_rate_card_id_and_cycle_index  (contract_rate_card_id,cycle_index) UNIQUE
#  index_billing_cycles_on_contract_rate_card_id_and_started_at   (contract_rate_card_id,started_at) UNIQUE
#  index_billing_cycles_on_organization_id                        (organization_id)
#
# Foreign Keys
#
#  fk_rails_...  (contract_rate_card_id => contract_rate_cards.id)
#  fk_rails_...  (organization_id => organizations.id)
#
