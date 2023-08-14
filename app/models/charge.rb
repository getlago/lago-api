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

  has_many :applied_taxes, class_name: 'Charge::AppliedTax', dependent: :destroy
  has_many :taxes, through: :applied_taxes

  CHARGE_MODELS = %i[
    standard
    graduated
    package
    percentage
    volume
    graduated_percentage
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

  validate :validate_group_properties
  validate :validate_pay_in_advance
  validate :validate_prorated
  validate :validate_min_amount_cents

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

  def validate_group_properties
    # Group properties should be set for all the selectable groups of a BM
    bm_group_ids = billable_metric.selectable_groups.pluck(:id).sort
    gp_group_ids = group_properties.map { |gp| gp[:group_id] }.compact.sort

    errors.add(:group_properties, :values_not_all_present) if bm_group_ids != gp_group_ids
  end

  # NOTE: An pay_in_advance charge cannot be created in the following cases:
  # - billable metric aggregation type is max_agg or recurring_count_agg
  # - charge model is volume
  def validate_pay_in_advance
    return unless pay_in_advance?
    return unless billable_metric.recurring_count_agg? || billable_metric.max_agg? || volume?

    errors.add(:pay_in_advance, :invalid_aggregation_type_or_charge_model)
  end

  def validate_min_amount_cents
    return unless pay_in_advance? && min_amount_cents.positive?

    errors.add(:min_amount_cents, :not_compatible_with_pay_in_advance)
  end

  # NOTE: A prorated charge cannot be created in the following cases:
  # - for pay_in_arrear, price model cannot be package, graduated and percentage
  # - for pay_in_idvance, price model cannot be package, graduated, percentage and volume
  def validate_prorated
    return unless prorated?
    return if billable_metric.recurring? && pay_in_advance? && standard?
    return if billable_metric.recurring? && !pay_in_advance? && (standard? || volume?)

    errors.add(:prorated, :invalid_billable_metric_or_charge_model)
  end
end
