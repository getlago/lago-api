# frozen_string_literal: true

class ChargeFilter < ApplicationRecord
  include PaperTrailTraceable
  include Discard::Model
  include ChargePropertiesValidation

  self.discard_column = :deleted_at

  belongs_to :charge, -> { with_discarded }, touch: true
  belongs_to :organization

  has_many :values, class_name: "ChargeFilterValue", dependent: :destroy
  has_many :billable_metric_filters, through: :values
  has_many :fees

  has_one :billable_metric, through: :charge

  validate :validate_properties

  # NOTE: Ensure filters are keeping the initial ordering
  default_scope -> { kept.order(updated_at: :asc) }

  CODE_SLUG_LIMIT = 200

  # A name for a filter. Removing a value from a billable metric trims it out of every filter using it,
  # so two filters can collapse onto the same values and stop being distinguishable:
  #
  #   {region: [us], tier: [gold]}    @0.02     ->  {region: [us]}  @0.02
  #   {region: [us], tier: [silver]}  @0.015    ->  {region: [us]}  @0.015
  # The code is derived at creation and never again, which is why the
  # backfill keeps an existing one instead of recomputing it.
  def self.generate_code(values_hash)
    canonical = values_hash.sort.map { |key, values| "#{key}:#{Array(values).sort.join("+")}" }.join("|")
    "#{canonical.parameterize(separator: "_").first(CODE_SLUG_LIMIT)}_#{Digest::SHA256.hexdigest(canonical).first(8)}"
  end

  # Add a suffix if duplicated, only for new ones
  def self.unique_code_for(charge_id, base_code)
    return base_code if charge_id.nil?

    next_free_code(base_code, where(charge_id:).unscope(:order).pluck(:code).compact.to_set)
  end

  # Callers that create several filters at once hold their own set, since the codes they hand out
  # are not in the table yet
  def self.next_free_code(base_code, taken)
    return base_code unless taken.include?(base_code)

    suffix = 2
    suffix += 1 while taken.include?("#{base_code}_#{suffix}")

    "#{base_code}_#{suffix}"
  end

  def display_name(separator: ", ")
    invoice_display_name.presence || (values.map do |value|
      next value.billable_metric_filter.key if value.values == [ChargeFilterValue::ALL_FILTER_VALUES]

      value.values
    end).flatten.join(separator)
  end

  def to_h
    @to_h ||= values_by_key(values)
  end

  def to_h_with_discarded
    @to_h_with_discarded ||= values_by_key(values.with_discarded)
  end

  def to_h_with_all_values
    @to_h_with_all_values ||= values.each_with_object({}) do |filter_value, result|
      values = filter_value.values
      values = filter_value.billable_metric_filter.values if values == [ChargeFilterValue::ALL_FILTER_VALUES]

      result[filter_value.billable_metric_filter.key] = values
    end.freeze
  end

  def assign_code!
    return if code.present?
    base_code = self.class.generate_code(values_by_key(values.reload))

    update_column(:code, self.class.unique_code_for(charge_id, base_code)) # rubocop:disable Rails/SkipsModelValidations
  end

  def pricing_group_keys
    properties["pricing_group_keys"].presence || properties["grouped_by"]
  end

  private

  def values_by_key(scope)
    scope.each_with_object({}) do |filter_value, result|
      result[filter_value.billable_metric_filter.key] = filter_value.values
    end.freeze
  end

  def validate_properties
    validate_charge_model_properties(charge&.charge_model)
  end
end

# == Schema Information
#
# Table name: charge_filters
# Database name: primary
#
#  id                   :uuid             not null, primary key
#  code                 :string
#  deleted_at           :datetime
#  invoice_display_name :string
#  properties           :jsonb            not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  charge_id            :uuid             not null
#  organization_id      :uuid             not null
#
# Indexes
#
#  index_active_charge_filters                 (charge_id) WHERE (deleted_at IS NULL)
#  index_charge_filters_on_charge_id           (charge_id)
#  index_charge_filters_on_charge_id_and_code  (charge_id,code) UNIQUE WHERE (deleted_at IS NULL)
#  index_charge_filters_on_deleted_at          (deleted_at)
#  index_charge_filters_on_organization_id     (organization_id)
#
# Foreign Keys
#
#  fk_rails_...  (charge_id => charges.id)
#  fk_rails_...  (organization_id => organizations.id)
#
