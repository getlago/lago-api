# frozen_string_literal: true

class ChargeFilter < ApplicationRecord
  include PaperTrailTraceable
  include Discard::Model
  self.discard_column = :deleted_at

  belongs_to :charge

  has_many :values, class_name: 'ChargeFilterValue', dependent: :destroy
  has_many :billable_metric_filters, through: :values
  has_many :fees

  validate :validate_properties

  default_scope -> { kept }

  def display_name
    invoice_display_name.presence || values.map(&:value).join(', ')
  end

  def to_h
    values.each_with_object({}) do |filter_value, result|
      result[filter_value.billable_metric_filter.key] = filter_value.value
    end
  end

  private

  def validate_properties
    case charge&.charge_model
    when 'standard'
      validate_charge_model(Charges::Validators::StandardService)
    when 'graduated'
      validate_charge_model(Charges::Validators::GraduatedService)
    when 'package'
      validate_charge_model(Charges::Validators::PackageService)
    when 'percentage'
      validate_charge_model(Charges::Validators::PercentageService)
    when 'volume'
      validate_charge_model(Charges::Validators::VolumeService)
    when 'graduated_percentage'
      validate_charge_model(Charges::Validators::GraduatedPercentageService)
    end
  end

  def validate_charge_model(validator)
    instance = validator.new(charge:, properties:)
    return if instance.valid?

    instance.result.error.messages.map { |_, codes| codes }
      .flatten
      .each { |code| errors.add(:properties, code) }
  end
end
