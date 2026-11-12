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
  end
end
