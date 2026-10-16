# frozen_string_literal: true

module ChargePropertiesValidation
  extend ActiveSupport::Concern

  PROPERTIES_VALIDATORS = {
    standard: Charges::Validators::StandardService,
    graduated: Charges::Validators::GraduatedService,
    package: Charges::Validators::PackageService,
    percentage: Charges::Validators::PercentageService,
    volume: Charges::Validators::VolumeService,
    graduated_percentage: Charges::Validators::GraduatedPercentageService
  }.freeze

  # Catalog rates and overrides store adjacent tiers (see RateProperties).
  RATE_PROPERTIES_VALIDATORS = PROPERTIES_VALIDATORS.merge(volume: Charges::Validators::AdjacentVolumeService).freeze

  def validate_charge_model_properties(charge_model)
    return unless charge_model

    validator = PROPERTIES_VALIDATORS[charge_model.to_sym]
    validator ||= Charges::Validators::BaseService

    instance = validator.new(charge: self)
    return if instance.valid?

    instance.result.error.messages.values.flatten.each { errors.add(:properties, it) }
  end
end
