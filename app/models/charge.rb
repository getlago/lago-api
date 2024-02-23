# frozen_string_literal: true

class Charge < ApplicationRecord
  include PaperTrailTraceable
  include Currencies
  include Discard::Model
  self.discard_column = :deleted_at

  belongs_to :plan, -> { with_discarded }, touch: true
  belongs_to :billable_metric, -> { with_discarded }
  belongs_to :charge_package_group, optional: true

  has_many :fees
  has_many :group_properties, dependent: :destroy

  has_many :applied_taxes, class_name: 'Charge::AppliedTax', dependent: :destroy
  has_many :taxes, through: :applied_taxes

  CHARGE_MODELS = %i[
    standard
    graduated
    package
    percentage
    volume
    graduated_percentage
    package_group
  ].freeze

  enum charge_model: CHARGE_MODELS

  validate :validate_amount, if: -> { standard? && group_properties.empty? }
  validate :validate_graduated, if: -> { graduated? && group_properties.empty? }
  validate :validate_package, if: -> { package? && group_properties.empty? }
  validate :validate_percentage, if: -> { percentage? && group_properties.empty? }
  validate :validate_volume, if: -> { volume? && group_properties.empty? }
  validate :validate_graduated_percentage, if: -> { graduated_percentage? && group_properties.empty? }

  validates :min_amount_cents, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :charge_model, presence: true

  validate :validate_pay_in_advance
  validate :validate_prorated
  validate :validate_min_amount_cents
  validate :validate_uniqueness_group_properties

  monetize :min_amount_cents, with_currency: ->(charge) { charge.plan.amount_currency }

  default_scope -> { kept }

  scope :pay_in_advance, -> { where(pay_in_advance: true) }

  def properties(group_id: nil)
    group_properties.find_by(group_id:)&.values || read_attribute(:properties)
  end

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

  # NOTE: An pay_in_advance charge cannot be created in the following cases:
  # - billable metric aggregation type is max_agg or weighted_sum_agg
  # - charge model is volume
  def validate_pay_in_advance
    return unless pay_in_advance?

    return unless %w[max_agg weighted_sum_agg latest_agg].include?(billable_metric.aggregation_type) || volume?

    errors.add(:pay_in_advance, :invalid_aggregation_type_or_charge_model)
  end

  def validate_min_amount_cents
    return unless pay_in_advance? && min_amount_cents.positive?

    errors.add(:min_amount_cents, :not_compatible_with_pay_in_advance)
  end

  # NOTE: A prorated charge cannot be created in the following cases:
  # - for pay_in_arrear, price model cannot be package, graduated and percentage
  # - for pay_in_idvance, price model cannot be package, graduated, percentage and volume
  # - for weighted_sum aggregation as it already apply pro-ration logic
  def validate_prorated
    return unless prorated?

    unless billable_metric.weighted_sum_agg?
      return if billable_metric.recurring? && pay_in_advance? && standard?
      return if billable_metric.recurring? && !pay_in_advance? && (standard? || volume? || graduated?)
    end

    errors.add(:prorated, :invalid_billable_metric_or_charge_model)
  end

  def validate_uniqueness_group_properties
    group_ids = group_properties.map(&:group_id)
    errors.add(:group_properties, :taken) if group_ids.size > group_ids.uniq.size
  end
end
