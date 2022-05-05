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
    validation_errors = Charges::GraduatedRangesService.new(properties).validate

    validation_errors.each { |error| errors.add(:properties, error) }
  end
end
