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
    volume
  ].freeze

  enum charge_model: CHARGE_MODELS

  validates :amount_currency, inclusion: { in: currency_list }
  validate :validate_amount, if: :standard?
  validate :validate_graduated_range, if: :graduated?
  validate :validate_package, if: :package?
  validate :validate_percentage, if: :percentage?
  validate :validate_volume, if: :volume?

  private

  def validate_amount
    validate_charge_model(Charges::Validators::StandardService)
  end

  def validate_graduated_range
    validate_charge_model(Charges::Validators::GraduatedService)
  end

  def validate_package
    validate_charge_model(Charges::Validators::PackageService)
  end

  def validate_percentage
    validate_charge_model(Charges::Validators::PercentageService)
  end

  def validate_volume
    validate_charge_model(Charges::Validators::VolumeService)
  end

  def validate_charge_model(validator)
    validation_result = validator.new(charge: self).validate
    return if validation_result.success?

    validation_result.error.each { |error| errors.add(:properties, error) }
  end
end
