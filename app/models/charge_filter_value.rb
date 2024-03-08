# frozen_string_literal: true

class ChargeFilterValue < ApplicationRecord
  include PaperTrailTraceable
  include Discard::Model
  self.discard_column = :deleted_at

  MATCH_ALL_FILTER_VALUES = '__LAGO_MATCH_ALL_FILTER_VALUES__'

  belongs_to :charge_filter
  belongs_to :billable_metric_filter

  validates :value, presence: true
  validate :validate_value

  default_scope -> { kept }

  private

  def validate_value
    return if value == MATCH_ALL_FILTER_VALUES
    return if billable_metric_filter&.values&.include?(value) # rubocop:disable Performance/InefficientHashSearch

    errors.add(:value, :inclusion)
  end
end
