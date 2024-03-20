# frozen_string_literal: true

class ChargeFilterValue < ApplicationRecord
  include PaperTrailTraceable
  include Discard::Model
  self.discard_column = :deleted_at

  MATCH_ALL_FILTER_VALUES = '__MATCH_ALL_FILTER_VALUES__'

  belongs_to :charge_filter
  belongs_to :billable_metric_filter, -> { with_discarded }

  validates :values, presence: true
  validate :validate_values

  default_scope -> { kept }

  delegate :key, to: :billable_metric_filter

  private

  def validate_values
    unless values.nil?
      return if values.count == 1 && values.first == MATCH_ALL_FILTER_VALUES
      return if values.all? { billable_metric_filter&.values&.include?(_1) } # rubocop:disable Performance/InefficientHashSearch
    end

    errors.add(:values, :inclusion)
  end
end
