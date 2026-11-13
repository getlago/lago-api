# frozen_string_literal: true

class ContractRecurringAggregationSnapshot < ApplicationRecord
  include RecurringAggregationSnapshotRecord

  BUCKET_COLUMN = :product_filter_id

  belongs_to :contract
  belongs_to :product, -> { with_discarded }
  belongs_to :product_filter, -> { with_discarded }, optional: true

  # A rate card prices one bucket, so every row of the bucket marks its period
  scope :period_markers, -> { all }

  # Bucket membership moves when a filter or value of the product changes, or when the contract prices
  # another filter of it, as priced filters take precedence. A value set to all values reads the metric
  # filter's values, which change without touching it. Checked in one round trip.
  def self.filters_changed_since?(organization_id:, contract_id:, product_id:, watermark:)
    changed = "created_at > :watermark OR deleted_at > :watermark"
    edited = "updated_at > :watermark OR deleted_at > :watermark"

    product_filters = ProductFilter.with_discarded.unscope(:order).where(organization_id:, product_id:)
    product_filter_values = ProductFilterValue.with_discarded.unscope(:order)
      .where(organization_id:, product_filter_id: product_filters.select(:id))
    all_values_metric_filters = BillableMetricFilter.with_discarded.unscope(:order)
      .where(organization_id:, id: product_filter_values.where(value: nil).select(:billable_metric_filter_id))
    contract_rate_cards = ContractRateCard.with_discarded.unscope(:order)
      .where(organization_id:, contract_id:, rate_card_id: RateCard.with_discarded.unscope(:order).where(organization_id:, product_id:).select(:id))

    checks = [
      product_filters.where(changed, watermark:),
      product_filter_values.where(edited, watermark:),
      all_values_metric_filters.where(edited, watermark:),
      contract_rate_cards.where(changed, watermark:)
    ]

    connection.select_value("SELECT #{checks.map { "EXISTS (#{it.select(1).to_sql})" }.join(" OR ")}")
  end
end

# == Schema Information
#
# Table name: contract_recurring_aggregation_snapshots
# Database name: primary
#
#  id                        :uuid             not null, primary key
#  events_count              :bigint           default(0), not null
#  grouped_by                :jsonb            not null
#  presentation_breakdowns   :jsonb            not null
#  priced_product_filter_ids :uuid             default([]), not null, is an Array
#  to_datetime               :datetime         not null
#  units                     :decimal(, )      default(0.0), not null
#  watermark                 :datetime         not null
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  billable_metric_id        :uuid             not null
#  contract_id               :uuid             not null
#  organization_id           :uuid             not null
#  product_filter_id         :uuid
#  product_id                :uuid             not null
#
# Indexes
#
#  idx_contract_recurring_snapshots_by_period              (contract_id,product_id,product_filter_id,to_datetime)
#  idx_contract_recurring_snapshots_on_billable_metric_id  (billable_metric_id)
#  idx_contract_recurring_snapshots_on_organization_id     (organization_id)
#  idx_contract_recurring_snapshots_on_product_filter_id   (product_filter_id)
#  idx_contract_recurring_snapshots_on_product_id          (product_id)
#  idx_contract_recurring_snapshots_unique                 (contract_id,product_id,product_filter_id,grouped_by,to_datetime) UNIQUE NULLS NOT DISTINCT
#
# Foreign Keys
#
#  fk_rails_...  (billable_metric_id => billable_metrics.id)
#  fk_rails_...  (contract_id => contracts.id)
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (product_filter_id => product_filters.id)
#  fk_rails_...  (product_id => products.id)
#
