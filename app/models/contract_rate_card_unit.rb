# frozen_string_literal: true

class ContractRateCardUnit < ApplicationRecord
  self.table_name = "contract_rate_cards_units"

  belongs_to :organization
  belongs_to :contract_rate_card, -> { with_discarded }, inverse_of: :units

  validates :effective_date, presence: true
  validates :effective_date, uniqueness: {scope: :contract_rate_card_id}
  validates :units, numericality: {greater_than_or_equal_to: 0}
  validate :organization_matches_contract_rate_card

  private

  def organization_matches_contract_rate_card
    return if contract_rate_card.nil? || organization_id == contract_rate_card.organization_id

    errors.add(:organization, :invalid)
  end
end

# == Schema Information
#
# Table name: contract_rate_cards_units
# Database name: primary
#
#  id                    :uuid             not null, primary key
#  effective_date        :date             not null
#  units                 :decimal(, )      not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  contract_rate_card_id :uuid             not null
#  organization_id       :uuid             not null
#
# Indexes
#
#  index_contract_rate_cards_units_on_card_and_effective_date  (contract_rate_card_id,effective_date) UNIQUE
#  index_contract_rate_cards_units_on_organization_id          (organization_id)
#
# Foreign Keys
#
#  fk_rails_...  (contract_rate_card_id => contract_rate_cards.id)
#  fk_rails_...  (organization_id => organizations.id)
#
