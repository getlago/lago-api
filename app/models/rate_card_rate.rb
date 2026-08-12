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
  validate :validate_rate_model_compatibility
  validate :validate_min_amount_timing
  validate :validate_properties

  default_scope -> { kept }

  scope :pending, -> { where("effective_from > ?", Time.current) }
  scope :effective, -> { where(effective_from: ..Time.current) }

  # The charge validators read pricing data from a `properties` attribute.
  def properties
    rate_properties
  end

  # Status is derived from the card's append-only timeline rather than stored:
  # the latest effective rate is active, future rates are pending, and earlier
  # effective rates have been superseded and are terminated.
  def status
    return STATUSES[:pending] if effective_from > Time.current

    now = Time.current
    siblings = rate_card.rates
    superseded =
      if siblings.loaded?
        siblings.any? { it.effective_from > effective_from && it.effective_from <= now }
      else
        siblings.where("effective_from > ?", effective_from).where(effective_from: ..now).exists?
      end

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

  # The property validators are shared with v1 charges and read the metric
  # from the record; expose the card's item metric under the same name.
  def billable_metric
    rate_card&.product&.billable_metric
  end

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

  def validate_rate_model_compatibility
    code = RateCardRates::ModelCompatibility.error_code(rate_model:, rate_card:)
    errors.add(:rate_model, code.to_sym) if code
  end

  # Minimum spending true-ups against a closed period, so it only exists on
  # arrears cards.
  def validate_min_amount_timing
    return unless min_amount_cents&.positive?
    return unless rate_card&.advance?

    errors.add(:min_amount_cents, :not_allowed_for_billing_timing)
  end

  # Append-only timeline: a new rate's effective_from must be strictly greater
  # than the latest existing rate on the same card. No insertion between rates.
  # The past is immutable, the future is editable
  def validate_effective_from_is_appended
    return if effective_from.blank?
    return if rate_card.blank?
    return unless new_record? || effective_from_changed?

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

  def validate_properties
    return unless rate_model
    return if errors[:rate_model].any?

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
