# frozen_string_literal: true

class RecurringAggregationSnapshot < ApplicationRecord
  belongs_to :organization
  belongs_to :subscription
  belongs_to :charge, -> { with_discarded }
  belongs_to :charge_filter, -> { with_discarded }, optional: true
  belongs_to :billable_metric, -> { with_discarded }

  validates :to_datetime, presence: true
  validates :watermark, presence: true
  validates :units, numericality: true
end

# == Schema Information
#
# Table name: recurring_aggregation_snapshots
# Database name: primary
#
#  id                 :uuid             not null, primary key
#  grouped_by         :jsonb            not null
#  to_datetime        :datetime         not null
#  units              :decimal(, )      default(0.0), not null
#  watermark          :datetime         not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  billable_metric_id :uuid             not null
#  charge_filter_id   :uuid
#  charge_id          :uuid             not null
#  organization_id    :uuid             not null
#  subscription_id    :uuid             not null
#
# Indexes
#
#  idx_recurring_aggregation_snapshots_unique                   (subscription_id,charge_id,charge_filter_id,grouped_by,to_datetime) UNIQUE NULLS NOT DISTINCT
#  index_recurring_aggregation_snapshots_on_billable_metric_id  (billable_metric_id)
#  index_recurring_aggregation_snapshots_on_charge_filter_id    (charge_filter_id)
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
