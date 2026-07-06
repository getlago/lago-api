# frozen_string_literal: true

class RateCardRate < ApplicationRecord
  include PaperTrailTraceable
  include ChargePropertiesValidation
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

  # allow_nil + explicit presence: a missing value reads as value_is_mandatory,
  # an unknown value as value_is_invalid.
  enum :rate_model, RATE_MODELS, validate: {allow_nil: true}
  enum :billing_interval_unit, BILLING_INTERVAL_UNITS, validate: {allow_nil: true}

  validates :billing_interval_unit, presence: true
  validates :effective_datetime, presence: true
  validates :rate_model, presence: true
  validates :min_amount_cents, numericality: {greater_than_or_equal_to: 0}
  validates :billing_interval_count, numericality: {greater_than_or_equal_to: 1}

  validate :validate_effective_datetime_is_appended
  validate :validate_pricing_unit_conversion_rate
  validate :validate_properties

  default_scope -> { kept }

  scope :pending, -> { where("effective_datetime > ?", Time.current) }
  scope :effective, -> { where(effective_datetime: ..Time.current) }

  # The charge validators read pricing data from a `properties` attribute.
  def properties
    rate_properties
  end

  # The charge-model calculators (ChargeModels::*) read the pricing model from
  # a `charge_model` attribute and check `prorated?`; expose both so a rate can
  # be priced through the same calculators as charges.
  def charge_model
    rate_model
  end

  def prorated?
    rate_card.proration?
  end

  # Status is derived from the card's append-only timeline rather than stored:
  # the latest effective rate is active, future rates are pending, and earlier
  # effective rates have been superseded and are terminated.
  def status
    return STATUSES[:pending] if effective_datetime > Time.current

    superseded = rate_card.rates
      .where("effective_datetime > ?", effective_datetime)
      .where(effective_datetime: ..Time.current)
      .exists?

    superseded ? STATUSES[:terminated] : STATUSES[:active]
  end

  def pending?
    status == STATUSES[:pending]
  end

  def active?
    status == STATUSES[:active]
  end

  def terminated?
    status == STATUSES[:terminated]
  end

  private

  # Append-only timeline: a new rate's effective_datetime must be strictly greater
  # than the latest existing rate on the same card. No insertion between rates.
  # The past is immutable, the future is editable: a rate can land anywhere in
  # the pending sequence, but never at or before the rate that already priced
  # elapsed time (the active one).
  def validate_effective_datetime_is_appended
    return if effective_datetime.blank?
    return if rate_card.blank?
    return unless new_record? || effective_datetime_changed?

    others = rate_card.rates.where.not(id:)
    if others.where(effective_datetime:).exists?
      errors.add(:effective_datetime, :value_already_exist)
      return
    end

    active_boundary = others.where(effective_datetime: ..Time.current).maximum(:effective_datetime)
    return if active_boundary.blank?
    return if effective_datetime > active_boundary

    errors.add(:effective_datetime, :must_be_after_active_rate)
  end

  def validate_pricing_unit_conversion_rate
    return if rate_card&.applied_pricing_unit_code.blank?
    return if applied_pricing_unit_conversion_rate.present?

    errors.add(:applied_pricing_unit_conversion_rate, :blank)
  end

  def validate_properties
    return unless rate_model

    validator = ChargePropertiesValidation::PROPERTIES_VALIDATORS[rate_model.to_sym]
    validator ||= Charges::Validators::BaseService

    instance = validator.new(charge: self)
    return if instance.valid?

    instance.result.error.messages.values.flatten.each { errors.add(:rate_properties, it) }
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
#  deleted_at                           :datetime
#  effective_datetime                   :datetime         not null
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
#  index_rate_card_rates_on_deleted_at                           (deleted_at)
#  index_rate_card_rates_on_organization_id                      (organization_id)
#  index_rate_card_rates_on_rate_card_id                         (rate_card_id)
#  index_rate_card_rates_on_rate_card_id_and_effective_datetime  (rate_card_id,effective_datetime) UNIQUE WHERE (deleted_at IS NULL)
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (rate_card_id => rate_cards.id)
#
