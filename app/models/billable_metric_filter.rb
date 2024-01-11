# frozen_string_literal: true

class BillableMetricFilter < ApplicationRecord
  include PaperTrailTraceable
  include Discard::Model
  self.discard_column = :deleted_at

  belongs_to :billable_metric

  has_many :filter_values, class_name: 'ChargeFilterValue', dependent: :destroy

  validates :key, presence: true
  validates :values, presence: true

  default_scope -> { kept }
end
