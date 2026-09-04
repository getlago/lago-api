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
  has_many :billing_segments

  validates :billing_anchor_date, presence: true
  validates :next_billing_at, presence: true
  validates :effective_date, presence: true
  validates :units, numericality: {greater_than_or_equal_to: 0}, allow_nil: true
  validates :rate_card_id, uniqueness: {scope: :contract_id, conditions: -> { where(deleted_at: nil, ended_date: nil) }}

  validate :validate_effective_before_ended

  default_scope -> { kept }

  # The window is day-grained and the end inclusive: the card still bills on
  # its ended_date, charges stop after it. Ended attachments are history;
  # upcoming ones stay visible. "Today" is the customer's day, not the
  # application's — same COALESCE chain as the v1 timezone SQL helpers.
  #
  # The plain date bound comes first: the timezone expression cannot use an
  # index, which turned a similar comparison into a full-scan timeout in the
  # termination clock (see #6086). Offsets span -12:00..+14:00, so any
  # customer-local today is at least yesterday's date — the bound is a strict
  # superset and the exact per-row check decides.
  scope :current_and_scheduled, -> {
    joins(contract: [:customer, :organization]).where(
      "contract_rate_cards.ended_date IS NULL OR (contract_rate_cards.ended_date >= ? AND " \
      "contract_rate_cards.ended_date >= " \
      "(?::timestamptz AT TIME ZONE COALESCE(customers.timezone, organizations.timezone, 'UTC'))::date)",
      Time.current.to_date - 1, Time.current
    )
  }

  def edit_error_code
    "contract_locked" unless contract.editable?
  end

  private

  def validate_effective_before_ended
    return if effective_date.blank? || ended_date.blank?
    return if effective_date <= ended_date

    errors.add(:ended_date, :must_be_after_effective_date)
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
#  effective_date      :date             not null
#  ended_date          :date
#  next_billing_at     :datetime         not null
#  units               :decimal(, )
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  contract_id         :uuid             not null
#  organization_id     :uuid             not null
#  rate_card_id        :uuid             not null
#
# Indexes
#
#  index_active_contract_rate_cards_on_contract_and_card  (contract_id,rate_card_id) UNIQUE WHERE ((deleted_at IS NULL) AND (ended_date IS NULL))
#  index_contract_rate_cards_on_contract_id               (contract_id)
#  index_contract_rate_cards_on_deleted_at                (deleted_at)
#  index_contract_rate_cards_on_next_billing_at           (next_billing_at) WHERE ((deleted_at IS NULL) AND (ended_date IS NULL))
#  index_contract_rate_cards_on_organization_id           (organization_id)
#  index_contract_rate_cards_on_rate_card_id              (rate_card_id)
#
# Foreign Keys
#
#  fk_rails_...  (contract_id => contracts.id)
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (rate_card_id => rate_cards.id)
#
