# frozen_string_literal: true

class ContractRateCard < ApplicationRecord
  include PaperTrailTraceable
  include Discard::Model

  self.discard_column = :deleted_at

  belongs_to :organization
  belongs_to :contract
  belongs_to :rate_card

  has_one :product, through: :rate_card

  has_many :rate_phases, -> { order(:position) }

  validates :billing_anchor_date, presence: true
  validates :next_billing_at, presence: true
  validates :started_at, presence: true
  validates :rate_card_id, uniqueness: {scope: :contract_id, conditions: -> { where(deleted_at: nil, ended_at: nil) }}

  validate :validate_started_before_ended

  default_scope -> { kept }

  private

  def validate_started_before_ended
    return if started_at.blank? || ended_at.blank?
    return if started_at <= ended_at

    errors.add(:ended_at, :must_be_after_started_at)
  end
end

# == Schema Information
#
# Table name: contract_rate_cards
# Database name: primary
#
#  id                  :uuid             not null, primary key
#  billing_anchor_date :date             not null
#  deleted_at          :datetime
#  ended_at            :datetime
#  next_billing_at     :datetime         not null
#  started_at          :datetime         not null
#  units               :decimal(, )
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  contract_id         :uuid             not null
#  organization_id     :uuid             not null
#  rate_card_id        :uuid             not null
#
# Indexes
#
#  index_active_contract_rate_cards_on_contract_and_card  (contract_id,rate_card_id) UNIQUE WHERE ((deleted_at IS NULL) AND (ended_at IS NULL))
#  index_contract_rate_cards_on_contract_id               (contract_id)
#  index_contract_rate_cards_on_deleted_at                (deleted_at)
#  index_contract_rate_cards_on_next_billing_at           (next_billing_at) WHERE ((deleted_at IS NULL) AND (ended_at IS NULL))
#  index_contract_rate_cards_on_organization_id           (organization_id)
#  index_contract_rate_cards_on_rate_card_id              (rate_card_id)
#
# Foreign Keys
#
#  fk_rails_...  (contract_id => contracts.id)
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (rate_card_id => rate_cards.id)
#
