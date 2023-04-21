# frozen_string_literal: true

class Charge < ApplicationRecord
  include PaperTrailTraceable
  include Currencies
  include Discard::Model
  self.discard_column = :deleted_at

  belongs_to :plan, touch: true
  belongs_to :billable_metric

  has_many :fees
  has_many :group_properties, dependent: :destroy

  CHARGE_MODELS = %i[
    standard
    graduated
    package
    percentage
    volume
  ].freeze

  enum charge_model: CHARGE_MODELS

  validate :validate_amount, if: -> { standard? && group_properties.empty? }
  validate :validate_graduated, if: -> { graduated? && group_properties.empty? }
  validate :validate_package, if: -> { package? && group_properties.empty? }
  validate :validate_percentage, if: -> { percentage? && group_properties.empty? }
  validate :validate_volume, if: -> { volume? && group_properties.empty? }

  validates :min_amount_cents, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  validate :validate_group_properties
  validate :validate_instant
  validate :validate_min_amount_cents

  monetize :min_amount_cents, with_currency: ->(charge) { charge.plan.amount_currency }

  default_scope -> { kept }

  scope :instant, -> { where(instant: true) }

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

  # NOTE: An instant charge cannot be created in the following cases:
  # - billable metric aggregation type is max_agg or recurring_count_agg
  # - charge model is volume
  def validate_instant
    return unless instant?
    return unless billable_metric.recurring_count_agg? || billable_metric.max_agg? || volume?

    errors.add(:instant, :invalid_aggregation_type_or_charge_model)
  end

  def validate_min_amount_cents
    return unless instant? && min_amount_cents.positive?

    errors.add(:min_amount_cents, :not_compatible_with_instant)
  end
end
