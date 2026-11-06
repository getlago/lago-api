# frozen_string_literal: true

class RecurringAggregationSnapshot < ApplicationRecord
  # An event ingested just before the aggregation may not be readable yet, so the next period counts it.
  # Same margin as the other enriched_at readers (ChargeFiltersScan::IncrementalCache::INGESTION_MARGIN).
  WATERMARK_LAG = 5.minutes

  AGGREGATION_TYPES = %w[sum_agg weighted_sum_agg].freeze

  belongs_to :organization
  belongs_to :subscription
  belongs_to :charge, -> { with_discarded }
  belongs_to :charge_filter, -> { with_discarded }, optional: true
  belongs_to :billable_metric, -> { with_discarded }

  validates :to_datetime, presence: true
  validates :watermark, presence: true
  validates :units, numericality: true

  # Compared to a scalar subquery: the period index then serves to_datetime, which an IN subquery does not
  scope :of_period, ->(to_datetime_query) { where(arel_table[:to_datetime].eq(Arel::Nodes::Grouping.new(to_datetime_query.arel))) }
  # The default bucket keeps a row for every closed period: its latest row before `before` marks the period.
  # One statement reads the marker and the buckets, so a run rewriting the period cannot land in between.
  scope :latest_period, lambda { |bucket_ids, before: nil|
    markers = where(charge_filter_id: nil)
    markers = markers.where(to_datetime: ...before) if before
    where(charge_filter_id: bucket_ids).of_period(markers.order(to_datetime: :desc).limit(1).select(:to_datetime))
  }
  # Chained after latest_period: the snapshots of one group, plus the first snapshot of each bucket for the
  # marker and the grouping keys check. Each part reads one bucket, so a whole group is one unique index lookup.
  # Stored groups hold a blank value as null, as the stores group it with a missing one. A key left out, such
  # as the target wallet of an event targeting none, matches every value.
  scope :of_group, lambda { |grouped_by_values, grouped_by_keys:, bucket_ids:|
    next if grouped_by_values.blank?

    group = if grouped_by_values.keys.sort == grouped_by_keys.map(&:to_s).sort
      where(grouped_by: grouped_by_values)
    else
      where("grouped_by @> ?", grouped_by_values.to_json)
    end
    parts = bucket_ids.flat_map do |bucket_id|
      [group.where(charge_filter_id: bucket_id).select(:id), where(charge_filter_id: bucket_id).select(:id).order(:grouped_by).limit(1)]
    end

    unscoped.where(arel_table[:id].in(parts.map { Arel::Nodes::Grouping.new(it.arel) }.reduce { Arel::Nodes::UnionAll.new(_1, _2) }))
  }

  # Snapshots are keyed on a subscription, which billing segments do not bill
  def self.eligible?(metered_item:, billing_context:)
    metered_item.billing_segment.nil? &&
      billing_context.subscription? &&
      AGGREGATION_TYPES.include?(metered_item.billable_metric.aggregation_type)
  end

  # Invoicing and pay in advance both check it, so they start the same charge from the same units
  def self.readable?(metered_item:, billing_context:)
    metered_item.billable_metric.recurring? &&
      eligible?(metered_item:, billing_context:) &&
      RecurringAggregationSnapshots.read_enabled?(billing_context.organization)
  end

  # Arguments of RecurringAggregationSnapshots::FetchService shared by invoicing and pay in advance,
  # so both select the same snapshots. grouped_by_keys follows the aggregation's own grouping.
  def self.fetch_arguments(metered_item:, billing_context:, grouped_by_keys: metered_item.pricing_group_keys)
    {
      subscription: billing_context.subscription,
      charge: metered_item.charge,
      charge_filter: metered_item.charge_filter,
      grouped_by_keys:,
      from_datetime: metered_item.boundaries.charges_from_datetime
    }
  end

  # A filter or filter value created, edited or removed since the marker moves older events between
  # buckets, so the snapshots of every bucket of the charges are stale, not only the one of that filter.
  # A value set to all values reads the metric filter's values, which change without touching it.
  def self.filters_changed_since?(organization_id:, charge_ids:, watermark:)
    charge_filters = ChargeFilter.with_discarded.unscope(:order).where(organization_id:, charge_id: charge_ids)
    charge_filter_values = ChargeFilterValue.with_discarded.unscope(:order)
      .where(organization_id:, charge_filter_id: charge_filters.select(:id))

    charge_filters.where("created_at > :watermark OR deleted_at > :watermark", watermark:).exists? ||
      charge_filter_values.where("updated_at > :watermark OR deleted_at > :watermark", watermark:).exists? ||
      BillableMetricFilter.with_discarded.unscope(:order)
        .where(
          organization_id:,
          id: charge_filter_values.where(values: [ChargeFilterValue::ALL_FILTER_VALUES]).select(:billable_metric_filter_id)
        )
        .where("updated_at > :watermark OR deleted_at > :watermark", watermark:)
        .exists?
  end
end

# == Schema Information
#
# Table name: recurring_aggregation_snapshots
# Database name: primary
#
#  id                      :uuid             not null, primary key
#  events_count            :bigint           default(0), not null
#  grouped_by              :jsonb            not null
#  presentation_breakdowns :jsonb            not null
#  to_datetime             :datetime         not null
#  units                   :decimal(, )      default(0.0), not null
#  watermark               :datetime         not null
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  billable_metric_id      :uuid             not null
#  charge_filter_id        :uuid
#  charge_id               :uuid             not null
#  organization_id         :uuid             not null
#  subscription_id         :uuid             not null
#
# Indexes
#
#  idx_recurring_aggregation_snapshots_unique                   (subscription_id,charge_id,charge_filter_id,grouped_by,to_datetime) UNIQUE NULLS NOT DISTINCT
#  index_recurring_aggregation_snapshots_by_period              (subscription_id,charge_id,charge_filter_id,to_datetime)
#  index_recurring_aggregation_snapshots_on_billable_metric_id  (billable_metric_id)
#  index_recurring_aggregation_snapshots_on_charge_filter_id    (charge_filter_id)
#  index_recurring_aggregation_snapshots_on_charge_id           (charge_id)
#  index_recurring_aggregation_snapshots_on_organization_id     (organization_id)
#
# Foreign Keys
#
#  fk_rails_...  (billable_metric_id => billable_metrics.id)
#  fk_rails_...  (charge_filter_id => charge_filters.id)
#  fk_rails_...  (charge_id => charges.id)
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (subscription_id => subscriptions.id)
#
