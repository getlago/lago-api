# frozen_string_literal: true

class ChargeFilterValue < ApplicationRecord
  include PaperTrailTraceable
  include Discard::Model
  self.discard_column = :deleted_at

  ALL_FILTER_VALUES = '__ALL_FILTER_VALUES__'

  belongs_to :charge_filter, -> { with_discarded }
  belongs_to :billable_metric_filter, -> { with_discarded }

  validates :values, presence: true
  validate :validate_values

  # NOTE: Ensure filters are keeping the initial ordering
  default_scope -> { kept.order(updated_at: :asc) }

  delegate :key, to: :billable_metric_filter

  private

  def validate_values
    unless values.nil?
      return if values.count == 1 && values.first == ALL_FILTER_VALUES
      return if values.all? { billable_metric_filter&.values&.include?(_1) } # rubocop:disable Performance/InefficientHashSearch
    end

    errors.add(:values, :inclusion)
  end
end
