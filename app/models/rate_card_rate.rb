# frozen_string_literal: true

class RateCardRate < ApplicationRecord
  include PaperTrailTraceable
  include Discard::Model

  self.discard_column = :deleted_at

  RATE_MODELS = {
    standard: "standard",
    graduated: "graduated",
    package: "package",
    percentage: "percentage",
    volume: "volume",
    graduated_percentage: "graduated_percentage",
    custom: "custom",
    dynamic: "dynamic"
  }.freeze

  BILLING_INTERVAL_UNITS = {
    day: "day",
    week: "week",
    month: "month",
    year: "year"
  }.freeze

  STATUSES = {
    pending: "pending",
    active: "active",
    terminated: "terminated"
  }.freeze

  belongs_to :organization
  belongs_to :rate_card

  has_many :fees

  # allow_nil here only keeps a missing value on the presence error
  # (value_is_mandatory) instead of also failing inclusion (value_is_invalid)
  enum :rate_model, RATE_MODELS, validate: {allow_nil: true}
  enum :billing_interval_unit, BILLING_INTERVAL_UNITS, validate: {allow_nil: true}

  validates :code, presence: true
  validates :code, uniqueness: {scope: :rate_card_id, conditions: -> { where(deleted_at: nil) }}
  validates :billing_interval_unit, presence: true
  # The column is a datetime: an unparseable value casts to nil
  validates :effective_from, presence: true, if: -> { effective_from_before_type_cast.blank? }
  validates :rate_model, presence: true
  validates :min_amount_cents, numericality: {greater_than_or_equal_to: 0}
  validates :billing_interval_count, numericality: {greater_than_or_equal_to: 1}

  before_validation :normalize_effective_from

  validate :validate_effective_from_parseable
  validate :validate_effective_from_is_appended
  validate :validate_pricing_unit_conversion_rate

  default_scope -> { kept }

  private

  # Arrears rates apply per whole day, Advance rates keep full
  # instants — they price per event
  def normalize_effective_from
    return if effective_from.blank?
    return unless rate_card&.arrears?

    self.effective_from = effective_from.beginning_of_day
  end

  def validate_effective_from_parseable
    return if effective_from.present?
    return if effective_from_before_type_cast.blank?

    errors.add(:effective_from, :invalid)
  end

  # Append-only timeline: a new rate's effective_from must be strictly greater
  # than the latest existing rate on the same card. No insertion between rates.
  # The past is immutable, the future is editable
  def validate_effective_from_is_appended
    return if effective_from.blank?
    return if rate_card.blank?

    others = rate_card.rates.where.not(id:)
    if others.where(effective_from:).exists?
      errors.add(:effective_from, :value_already_exist)
      return
    end

    active_boundary = others.where(effective_from: ..Time.current).maximum(:effective_from)
    return if active_boundary.blank?
    return if effective_from > active_boundary

    errors.add(:effective_from, :must_be_after_active_rate)
  end

  def validate_pricing_unit_conversion_rate
    return if rate_card&.applied_pricing_unit_code.blank?
    return if applied_pricing_unit_conversion_rate.present?

    errors.add(:applied_pricing_unit_conversion_rate, :blank)
  end
end

# == Schema Information
#
# Table name: rate_card_rates
# Database name: primary
#
#  id                                   :uuid             not null, primary key
#  applied_pricing_unit_conversion_rate :decimal(30, 10)
#  billing_interval_count               :integer          default(1), not null
#  billing_interval_unit                :enum             not null
#  code                                 :string           not null
#  deleted_at                           :datetime
#  effective_from                       :datetime         not null
#  min_amount_cents                     :bigint           default(0), not null
#  rate_model                           :enum             not null
#  rate_properties                      :jsonb            not null
#  created_at                           :datetime         not null
#  updated_at                           :datetime         not null
#  organization_id                      :uuid             not null
#  rate_card_id                         :uuid             not null
#
# Indexes
#
#  index_rate_card_rates_on_deleted_at                       (deleted_at)
#  index_rate_card_rates_on_organization_id                  (organization_id)
#  index_rate_card_rates_on_rate_card_id                     (rate_card_id)
#  index_rate_card_rates_on_rate_card_id_and_code            (rate_card_id,code) UNIQUE WHERE (deleted_at IS NULL)
#  index_rate_card_rates_on_rate_card_id_and_effective_from  (rate_card_id,effective_from) UNIQUE WHERE (deleted_at IS NULL)
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (rate_card_id => rate_cards.id)
#
