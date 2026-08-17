# frozen_string_literal: true

class SubscriptionRateCard < ApplicationRecord
  include PaperTrailTraceable
  include Discard::Model
  include RatePhaseable

  self.discard_column = :deleted_at

  belongs_to :organization
  belongs_to :subscription
  belongs_to :customer
  belongs_to :rate_card

  has_one :product, through: :rate_card

  has_many :rate_phases, -> { order(:position) }
  has_many :billing_cycles

  delegate :proration?, to: :rate_card

  validates :billing_anchor_date, presence: true
  validates :next_billing_at, presence: true
  validates :started_at, presence: true
  validates :rate_card_id, uniqueness: {scope: :subscription_id, conditions: -> { where(deleted_at: nil, ended_at: nil) }}

  validate :validate_started_before_ended

  default_scope -> { kept }

  # An entry is versioned on units changes: rows are time-bounded by
  # [started_at, ended_at). active_at picks the version in force at a given
  # time; current_and_scheduled hides superseded history but keeps upcoming
  # versions visible.
  scope :active_at, ->(time) { where(started_at: ..time).where("ended_at IS NULL OR ended_at > ?", time) }
  scope :current_and_scheduled, -> { where("ended_at IS NULL OR ended_at > ?", Time.current) }
  scope :due_for_range, ->(range) {
    range_begin = range.begin.to_date.beginning_of_day.utc
    range_end = range.end.to_date.end_of_day.utc

    where(started_at: ..range_end)
      .where("ended_at IS NULL OR ended_at >= ?", range_begin)
      .where(next_billing_at: ..range_end)
  }

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
#  customer_id         :uuid             not null
#  organization_id     :uuid             not null
#  rate_card_id        :uuid             not null
#  subscription_id     :uuid             not null
#
# Indexes
#
#  index_active_subscription_rate_cards_on_sub_and_card  (subscription_id,rate_card_id) UNIQUE WHERE ((deleted_at IS NULL) AND (ended_at IS NULL))
#  index_subscription_rate_cards_on_customer_id          (customer_id)
#  index_subscription_rate_cards_on_deleted_at           (deleted_at)
#  index_subscription_rate_cards_on_next_billing_at      (next_billing_at) WHERE ((deleted_at IS NULL) AND (ended_at IS NULL))
#  index_subscription_rate_cards_on_organization_id      (organization_id)
#  index_subscription_rate_cards_on_rate_card_id         (rate_card_id)
#  index_subscription_rate_cards_on_subscription_id      (subscription_id)
#
# Foreign Keys
#
#  fk_rails_...  (customer_id => customers.id)
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (rate_card_id => rate_cards.id)
#  fk_rails_...  (subscription_id => subscriptions.id)
#
