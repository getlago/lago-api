# frozen_string_literal: true

class RateOverride < ApplicationRecord
  include PaperTrailTraceable
  include ChargePropertiesValidation
  include Discard::Model

  self.discard_column = :deleted_at

  # A rate override mirrors the overridable pricing fields of a rate_card_rate.
  # Structural card fields (currency, billing timing, proration, ...) are never
  # overridden here and are always inherited from the rate card.
  RATE_MODELS = RateCardRate::RATE_MODELS
  BILLING_INTERVAL_UNITS = RateCardRate::BILLING_INTERVAL_UNITS

  belongs_to :organization

  has_many :rate_phases
  has_many :fees

  enum :rate_model, RATE_MODELS, validate: true
  enum :billing_interval_unit, BILLING_INTERVAL_UNITS, validate: {allow_nil: true}

  validates :min_amount_cents, numericality: {greater_than_or_equal_to: 0}
  validates :billing_interval_count, numericality: {greater_than_or_equal_to: 1}, allow_nil: true

  validate :validate_properties

  default_scope -> { kept }

  # The charge validators read pricing data from a `properties` attribute.
  def properties
    rate_properties
  end

  private

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
# Table name: rate_overrides
# Database name: primary
#
#  id                           :uuid             not null, primary key
#  billing_interval_count       :integer
#  billing_interval_unit        :enum
#  deleted_at                   :datetime
#  min_amount_cents             :bigint           default(0), not null
#  pricing_unit_conversion_rate :decimal(30, 10)
#  rate_model                   :enum             not null
#  rate_properties              :jsonb            not null
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#  organization_id              :uuid             not null
#
# Indexes
#
#  index_rate_overrides_on_deleted_at       (deleted_at)
#  index_rate_overrides_on_organization_id  (organization_id)
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#
