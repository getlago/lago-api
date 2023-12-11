# frozen_string_literal: true

class BillableMetric < ApplicationRecord
  include PaperTrailTraceable
  include Discard::Model
  self.discard_column = :deleted_at

  belongs_to :organization

  has_many :charges, dependent: :destroy
  has_many :groups, dependent: :delete_all
  has_many :plans, through: :charges
  has_many :quantified_events
  has_many :coupon_targets
  has_many :coupons, through: :coupon_targets

  AGGREGATION_TYPES = {
    count_agg: 0,
    sum_agg: 1,
    max_agg: 2,
    unique_count_agg: 3,
    # NOTE: deleted aggregation type, recurring_count_agg: 4,
    weighted_sum_agg: 5,
    latest_agg: 6,
  }.freeze

  WEIGHTED_INTERVAL = { seconds: 'seconds' }.freeze

  enum aggregation_type: AGGREGATION_TYPES
  enum weighted_interval: WEIGHTED_INTERVAL

  validate :validate_recurring

  validates :name, presence: true
  validates :field_name, presence: true, if: :should_have_field_name?
  validates :aggregation_type, inclusion: { in: AGGREGATION_TYPES.keys.map(&:to_s) }
  validates :code,
            presence: true,
            uniqueness: { conditions: -> { where(deleted_at: nil) }, scope: :organization_id }
  validates :weighted_interval,
            inclusion: { in: WEIGHTED_INTERVAL.values },
            if: :weighted_sum_agg?

  default_scope -> { kept }

  def self.ransackable_attributes(_auth_object = nil)
    %w[name code]
  end

  def attached_to_subscriptions?
    plans.joins(:subscriptions).exists?
  end

  def aggregation_type=(value)
    AGGREGATION_TYPES.key?(value&.to_sym) ? super : nil
  end

  def active_groups
    scope = groups.order(created_at: :asc)
    scope = scope.with_discarded if discarded?
    scope
  end

  # NOTE: 1 dimension: all groups, 2 dimensions: all children.
  def selectable_groups
    groups = active_groups.children.exists? ? active_groups.children : active_groups
    groups.includes(:parent).reorder('parent.value', 'groups.value')
  end

  def active_groups_as_tree
    return {} if active_groups.blank?

    unless active_groups.children.exists?
      return {
        key: active_groups.pluck(:key).uniq.first,
        values: active_groups.pluck(:value),
      }
    end

    {
      key: active_groups.parents.pluck(:key).uniq.first,
      values: active_groups.parents.map do |p|
        {
          name: p.value,
          key: p.children.first.key,
          values: p.children.pluck(:value),
        }
      end,
    }
  end

  private

  def should_have_field_name?
    !count_agg?
  end

  def validate_recurring
    return unless recurring?
    return unless count_agg? || max_agg? || latest_agg?

    errors.add(:recurring, :not_compatible_with_aggregation_type)
  end
end
