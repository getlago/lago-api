# frozen_string_literal: true

class BillableMetric < ApplicationRecord
  include Discard::Model
  self.discard_column = :deleted_at

  belongs_to :organization

  has_many :charges, dependent: :destroy
  has_many :groups, dependent: :delete_all
  has_many :plans, through: :charges
  has_many :persisted_events

  AGGREGATION_TYPES = %i[
    count_agg
    sum_agg
    max_agg
    unique_count_agg
    recurring_count_agg
  ].freeze

  enum aggregation_type: AGGREGATION_TYPES

  validates :name, presence: true
  validates :code, presence: true, uniqueness: { scope: :organization_id }
  validates :field_name, presence: true, if: :should_have_field_name?
  validates :aggregation_type, inclusion: { in: AGGREGATION_TYPES.map(&:to_s) }

  default_scope -> { kept }

  def attached_to_subscriptions?
    plans.joins(:subscriptions).exists?
  end

  def deletable?
    !attached_to_subscriptions?
  end

  def aggregation_type=(value)
    AGGREGATION_TYPES.include?(value&.to_sym) ? super : nil
  end

  def active_groups
    groups.active.order(created_at: :asc)
  end

  # NOTE: 1 dimension: all groups, 2 dimensions: all children.
  def selectable_groups
    active_groups.children.exists? ? active_groups.children : active_groups
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
end
