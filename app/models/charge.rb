# frozen_string_literal: true

class Charge < ApplicationRecord
  include Currencies

  belongs_to :plan, touch: true
  belongs_to :billable_metric

  has_many :fees

  CHARGE_MODELS = %i[
    standard
    graduated
    package
    percentage
  ].freeze

  FIXED_AMOUNT_TARGETS = %w[
    all_units
    each_unit
  ].freeze

  enum charge_model: CHARGE_MODELS

  validate :validate_currency
  validate :validate_amount, if: :standard?
  validate :validate_graduated_range, if: :graduated?
  validate :validate_package, if: :package?
  validate :validate_percentage, if: :percentage?

  private

  def validate_amount
    validation_result = Charges::Validators::StandardService.new(charge: self).validate
    return if validation_result.success?

    validation_result.error.each { |error| errors.add(:properties, error) }
  end

  def validate_graduated_range
    validation_result = Charges::Validators::GraduatedService.new(charge: self).validate
    return if validation_result.success?

    validation_result.error.each { |error| errors.add(:properties, error) }
  end

  def validate_package
    validation_result = Charges::Validators::PackageService.new(charge: self).validate
    return if validation_result.success?

    validation_result.error.each { |error| errors.add(:properties, error) }
  end

  def validate_percentage
    validation_result = Charges::Validators::PercentageService.new(charge: self).validate
    return if validation_result.success?

    validation_result.error.each { |error| errors.add(:properties, error) }
  end

  def validate_currency
    return if plan.amount_currency == amount_currency

    errors.add(:amount_currency, :plan_has_different_currency)
  end
end
