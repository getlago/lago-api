# frozen_string_literal: true

class BillableMetric < ApplicationRecord
  belongs_to :organization

  BILLABLE_PERIODS = %i[
    recurring
    one_shot
  ].freeze

  AGGREGATION_TYPES = %i[
    count
    sum
    max_count
    unique_count
  ].freeze

  enum billable_period: BILLABLE_PERIODS
  enum aggregation_type: AGGREGATION_TYPES, _suffix: :agg

  validates :name, presence: true
  validates :code, presence: true, uniqueness: { scope: :organization_id }
  validates :pro_rata, presence: true, inclusion: { in: [true, false] }
end
