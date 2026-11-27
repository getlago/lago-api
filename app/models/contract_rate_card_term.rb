# frozen_string_literal: true

class ContractRateCardTerm < ApplicationRecord
  self.table_name = "contract_rate_cards_terms"

  APPLICATION_TIMINGS = {
    current_billing_cycle: "current_billing_cycle",
    next_billing_cycle: "next_billing_cycle"
  }.freeze

  enum :application_timing, APPLICATION_TIMINGS, default: :current_billing_cycle, validate: true

  belongs_to :organization
  belongs_to :contract_rate_card, -> { with_discarded }, inverse_of: :terms

  validates :effective_date, presence: true
  validates :effective_date, uniqueness: {scope: :contract_rate_card_id, conditions: -> { current_billing_cycle }}, if: :current_billing_cycle?
  validates :units, numericality: {greater_than_or_equal_to: 0}
  validate :organization_matches_contract_rate_card

  def starts_at
    effective_date.in_time_zone(contract_rate_card.contract.customer.applicable_timezone)
  end

  private

  def organization_matches_contract_rate_card
    return if contract_rate_card.nil? || organization_id == contract_rate_card.organization_id

    errors.add(:organization, :invalid)
  end
end

# == Schema Information
#
# Table name: contract_rate_cards_terms
# Database name: primary
#
#  id                    :uuid             not null, primary key
#  application_timing    :enum             default("current_billing_cycle"), not null
#  effective_date        :date             not null
#  units                 :decimal(, )      not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  contract_rate_card_id :uuid             not null
#  organization_id       :uuid             not null
#
# Indexes
#
#  index_contract_rate_card_terms_by_date              (contract_rate_card_id,effective_date)
#  index_contract_rate_cards_terms_on_organization_id  (organization_id)
#  index_current_contract_rate_card_terms              (contract_rate_card_id,effective_date) UNIQUE WHERE (application_timing = 'current_billing_cycle'::contract_rate_cards_terms_application_timing)
#
# Foreign Keys
#
#  fk_rails_...  (contract_rate_card_id => contract_rate_cards.id)
#  fk_rails_...  (organization_id => organizations.id)
#
