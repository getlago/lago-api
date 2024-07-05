# frozen_string_literal: true

class Charge < ApplicationRecord
  include PaperTrailTraceable
  include Currencies
  include Discard::Model
  self.discard_column = :deleted_at

  belongs_to :plan, -> { with_discarded }, touch: true
  belongs_to :billable_metric, -> { with_discarded }

  has_many :fees
  has_many :group_properties, dependent: :destroy
  has_many :filters, dependent: :destroy, class_name: 'ChargeFilter'
  has_many :filter_values, through: :filters, class_name: 'ChargeFilterValue', source: :values

  has_many :applied_taxes, class_name: 'Charge::AppliedTax', dependent: :destroy
  has_many :taxes, through: :applied_taxes

  CHARGE_MODELS = %i[
    standard
    graduated
    package
    percentage
    volume
    graduated_percentage
    custom
  ].freeze

  REGROUPING_PAID_FEES_OPTIONS = %i[invoice].freeze

  enum charge_model: CHARGE_MODELS
  enum regroup_paid_fees: REGROUPING_PAID_FEES_OPTIONS

  validate :validate_amount, if: -> { standard? && group_properties.empty? }
  validate :validate_graduated, if: -> { graduated? && group_properties.empty? }
  validate :validate_package, if: -> { package? && group_properties.empty? }
  validate :validate_percentage, if: -> { percentage? && group_properties.empty? }
  validate :validate_volume, if: -> { volume? && group_properties.empty? }
  validate :validate_graduated_percentage, if: -> { graduated_percentage? && group_properties.empty? }

  validates :min_amount_cents, numericality: {greater_than_or_equal_to: 0}, allow_nil: true
  validates :charge_model, presence: true

  validate :validate_pay_in_advance
  validate :validate_regroup_paid_fees
  validate :validate_prorated
  validate :validate_min_amount_cents
  validate :validate_custom_model

  monetize :min_amount_cents, with_currency: ->(charge) { charge.plan.amount_currency }

  default_scope -> { kept }

  scope :pay_in_advance, -> { where(pay_in_advance: true) }

  private

  def validate_amount
    validate_charge_model(Charges::Validators::StandardService)
  end

  def validate_graduated
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

  def validate_graduated_percentage
    validate_charge_model(Charges::Validators::GraduatedPercentageService)
  end

  def validate_charge_model(validator)
    instance = validator.new(charge: self)
    return if instance.valid?

    instance.result.error.messages.map { |_, codes| codes }
      .flatten
      .each { |code| errors.add(:properties, code) }
  end

  def validate_pay_in_advance
    return unless pay_in_advance?

    if volume? || !billable_metric.payable_in_advance?
      errors.add(:pay_in_advance, :invalid_aggregation_type_or_charge_model)
    end
  end

  # NOTE: regroup_paid_fees only works with pay_in_advance and non-invoiceable charges
  def validate_regroup_paid_fees
    return if regroup_paid_fees.nil?
    return if pay_in_advance? && !invoiceable?

    errors.add(:regroup_paid_fees, :only_compatible_with_pay_in_advance_and_non_invoiceable)
  end

  def validate_min_amount_cents
    return unless pay_in_advance? && min_amount_cents.positive?

    errors.add(:min_amount_cents, :not_compatible_with_pay_in_advance)
  end

  # NOTE: A prorated charge cannot be created in the following cases:
  # - for pay_in_arrears, price model cannot be package, graduated and percentage
  # - for pay_in_advance, price model cannot be package, graduated, percentage and volume
  # - for weighted_sum aggregation as it already apply pro-ration logic
  def validate_prorated
    return unless prorated?

    unless billable_metric.weighted_sum_agg?
      return if billable_metric.recurring? && pay_in_advance? && standard?
      return if billable_metric.recurring? && !pay_in_advance? && (standard? || volume? || graduated?)
    end

    errors.add(:prorated, :invalid_billable_metric_or_charge_model)
  end

  def validate_custom_model
    return unless custom?
    return if billable_metric.custom_agg?

    errors.add(:charge_model, :invalid_aggregation_type_or_charge_model)
  end
end
