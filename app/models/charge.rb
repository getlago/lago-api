# frozen_string_literal: true

class Charge < ApplicationRecord
  include Currencies

  belongs_to :plan
  belongs_to :billable_metric

  has_many :fees

  CHARGE_MODELS = %i[
    standard
    graduated
  ].freeze

  enum charge_model: CHARGE_MODELS

  monetize :amount_cents

  validates :amount_currency, inclusion: { in: currency_list }
  validate :validate_graduated_range, if: :graduated?

  def validate_graduated_range
    validation_result = Charges::GraduatedRangesService.new(ranges: properties).validate
    return if validation_result.success?

    validation_result.error.each { |error| errors.add(:properties, error) }
  end
end
