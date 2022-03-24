# frozen_string_literal: true

class BillableMetric < ApplicationRecord
  belongs_to :organization

  has_many :charges, dependent: :destroy
  has_many :plans, through: :charges

  BILLABLE_PERIODS = %i[
    one_shot
    recurring
  ].freeze

  AGGREGATION_TYPES = %i[
    count_agg
    sum_agg
    max_count_agg
    unique_count_agg
  ].freeze

  enum billable_period: BILLABLE_PERIODS
  enum aggregation_type: AGGREGATION_TYPES

  validates :name, presence: true
  validates :code, presence: true, uniqueness: { scope: :organization_id }
end
