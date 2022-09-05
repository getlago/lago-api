# frozen_string_literal: true

class BillableMetric < ApplicationRecord
  belongs_to :organization

  has_many :charges, dependent: :destroy
  has_many :plans, through: :charges
  has_many :persisted_events

  BILLABLE_PERIODS = %i[
    one_shot
    recurring
  ].freeze

  AGGREGATION_TYPES = %i[
    count_agg
    sum_agg
    max_agg
    unique_count_agg
    recurring_count_agg
  ].freeze

  enum billable_period: BILLABLE_PERIODS
  enum aggregation_type: AGGREGATION_TYPES

  validates :name, presence: true
  validates :code, presence: true, uniqueness: { scope: :organization_id }
  validates :field_name, presence: true, if: :should_have_field_name?

  def attached_to_subscriptions?
    plans.joins(:subscriptions).exists?
  end

  def deletable?
    !attached_to_subscriptions?
  end

  private

  def should_have_field_name?
    !count_agg?
  end
end
