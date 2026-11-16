# frozen_string_literal: true

class ContractRecurringAggregationSnapshot < ApplicationRecord
  include RecurringAggregationSnapshotRecord

  belongs_to :contract
  belongs_to :product, -> { with_discarded }
  belongs_to :product_filter, -> { with_discarded }, optional: true
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
