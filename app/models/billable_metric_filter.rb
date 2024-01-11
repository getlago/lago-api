# frozen_string_literal: true

class BillableMetricFilter < ApplicationRecord
  include PaperTrailTraceable
  include Discard::Model
  self.discard_column = :deleted_at

  belongs_to :billable_metric

  validates :key, presence: true
  validates :values, presence: true
end
