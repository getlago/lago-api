# frozen_string_literal: true

class RecurringAggregationSnapshot < ApplicationRecord
  include RecurringAggregationSnapshotRecord

  BUCKET_COLUMN = :charge_filter_id

  belongs_to :subscription
  belongs_to :charge, -> { with_discarded }
  belongs_to :charge_filter, -> { with_discarded }, optional: true

  # The default bucket keeps a row for every closed period, which marks the period for all buckets
  scope :period_markers, -> { where(charge_filter_id: nil) }

  # A charge is snapshotted under its subscription, a billing segment under its contract
  def self.eligible?(metered_item:, billing_context:)
    owner_context = metered_item.billing_segment ? billing_context.contract? : billing_context.subscription?

    owner_context && AGGREGATION_TYPES.include?(metered_item.billable_metric.aggregation_type)
  end

  # Invoicing and pay in advance both check it, so they start the same charge from the same units
  def self.readable?(metered_item:, billing_context:)
    metered_item.billable_metric.recurring? &&
      eligible?(metered_item:, billing_context:) &&
      RecurringAggregationSnapshots.read_enabled?(billing_context.organization)
  end

  def self.key(metered_item:, billing_context:)
    if metered_item.billing_segment
      RecurringAggregationSnapshots::ContractKey.new(
        contract: billing_context.contract,
        product: metered_item.invoiceable,
        product_filter: metered_item.contract_rate_card.rate_card.product_filter
      )
    else
      RecurringAggregationSnapshots::SubscriptionKey.new(subscription: billing_context.subscription, charge: metered_item.charge)
    end
  end

  # Arguments of RecurringAggregationSnapshots::FetchService shared by invoicing and pay in advance,
  # so both select the same snapshots. grouped_by_keys follows the aggregation's own grouping.
  def self.fetch_arguments(metered_item:, billing_context:, grouped_by_keys: metered_item.pricing_group_keys)
    {
      key: key(metered_item:, billing_context:),
      filter: metered_item.selected_filter,
      grouped_by_keys:,
      from_datetime: metered_item.boundaries.charges_from_datetime,
      period_attributes: period_attributes(metered_item:)
    }
  end

  # Columns every row of a period stores, which a read must match to reuse the period.
  # Priced filters take precedence over the product's other filters, and a segment's set can change
  # with no row changing (BillingSegment#priced_product_filter_ids).
  def self.period_attributes(metered_item:)
    return {} unless metered_item.billing_segment

    {priced_product_filter_ids: metered_item.billing_segment.priced_product_filter_ids.uniq.sort}
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
