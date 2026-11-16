# frozen_string_literal: true

# Shared by the snapshots of subscriptions and of contracts, which store the same values under a different key.
module RecurringAggregationSnapshotRecord
  extend ActiveSupport::Concern

  # An event ingested just before the aggregation may not be readable yet, so the next period counts it.
  # Same margin as the other enriched_at readers (ChargeFiltersScan::IncrementalCache::INGESTION_MARGIN).
  WATERMARK_LAG = 5.minutes

  AGGREGATION_TYPES = %w[sum_agg weighted_sum_agg].freeze

  included do
    belongs_to :organization
    belongs_to :billable_metric, -> { with_discarded }

    validates :to_datetime, presence: true
    validates :watermark, presence: true
    validates :units, numericality: true

    # Compared to a scalar subquery: the period index then serves to_datetime, which an IN subquery does not
    scope :of_period, ->(to_datetime_query) { where(arel_table[:to_datetime].eq(Arel::Nodes::Grouping.new(to_datetime_query.arel))) }
    # The latest marker before `before` marks the period (see period_markers).
    # One statement reads the marker and the buckets, so a run rewriting the period cannot land in between.
    scope :latest_period, lambda { |bucket_ids, before: nil|
      markers = period_markers
      markers = markers.where(to_datetime: ...before) if before
      where(klass::BUCKET_COLUMN => bucket_ids).of_period(markers.order(to_datetime: :desc).limit(1).select(:to_datetime))
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
        [group.where(klass::BUCKET_COLUMN => bucket_id).select(:id), where(klass::BUCKET_COLUMN => bucket_id).select(:id).order(:grouped_by).limit(1)]
      end

      unscoped.where(arel_table[:id].in(parts.map { Arel::Nodes::Grouping.new(it.arel) }.reduce { Arel::Nodes::UnionAll.new(_1, _2) }))
    }
  end
end
