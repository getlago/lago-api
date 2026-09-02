# frozen_string_literal: true

class SubscriptionRateCard < ApplicationRecord
  include PaperTrailTraceable
  include Discard::Model
  include RatePhaseable

  self.discard_column = :deleted_at

  belongs_to :organization
  belongs_to :subscription
  belongs_to :rate_card

  has_one :product, through: :rate_card

  has_many :rate_phases, -> { order(:position) }

  validates :billing_anchor_date, presence: true
  validates :next_billing_at, presence: true
  validates :started_at, presence: true
  validates :rate_card_id, uniqueness: {scope: :subscription_id, conditions: -> { where(deleted_at: nil, ended_at: nil) }}

  validate :validate_started_before_ended

  validates :units, numericality: {greater_than_or_equal_to: 0}, allow_nil: true

  default_scope -> { kept }

  # An entry is versioned on units changes: rows are time-bounded by
  # [started_at, ended_at). active_at picks the version in force at a given
  # time; current_and_scheduled hides superseded history but keeps upcoming
  # versions visible.
  scope :active_at, ->(time) { where(started_at: ..time).where("ended_at IS NULL OR ended_at > ?", time) }
  scope :current_and_scheduled, -> { where("ended_at IS NULL OR ended_at > ?", Time.current) }

  private

  def validate_started_before_ended
    return if started_at.blank? || ended_at.blank?
    return if started_at <= ended_at

    errors.add(:ended_at, :must_be_after_started_at)
  end
end

# == Schema Information
#
# Table name: subscription_rate_cards
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
#  organization_id     :uuid             not null
#  rate_card_id        :uuid             not null
#  subscription_id     :uuid             not null
#
# Indexes
#
#  index_active_subscription_rate_cards_on_sub_and_card  (subscription_id,rate_card_id) UNIQUE WHERE ((deleted_at IS NULL) AND (ended_at IS NULL))
#  index_subscription_rate_cards_on_deleted_at           (deleted_at)
#  index_subscription_rate_cards_on_next_billing_at      (next_billing_at) WHERE ((deleted_at IS NULL) AND (ended_at IS NULL))
#  index_subscription_rate_cards_on_organization_id      (organization_id)
#  index_subscription_rate_cards_on_rate_card_id         (rate_card_id)
#  index_subscription_rate_cards_on_subscription_id      (subscription_id)
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (rate_card_id => rate_cards.id)
#  fk_rails_...  (subscription_id => subscriptions.id)
#
