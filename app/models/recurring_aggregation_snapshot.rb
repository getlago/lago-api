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
      billing_context.organization.feature_flag_enabled?(:persisted_recurring_values)
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
