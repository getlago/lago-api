# frozen_string_literal: true

class BillableMetricFilter < ApplicationRecord
  include PaperTrailTraceable
  include Discard::Model
  self.discard_column = :deleted_at

  belongs_to :billable_metric, -> { with_discarded }

  has_many :filter_values, class_name: 'ChargeFilterValue', dependent: :destroy
  has_many :charge_filters, through: :filter_values

  validates :key, presence: true
  validates :values, presence: true

  default_scope -> { kept }
end
