# frozen_string_literal: true

# Live current-period usage per (subscription, charge, filter, grouped_by),
# written by the RisingWave pipeline (extra/risingwave) through a Postgres
# sink. Rows exist for open billing periods only — the pipeline retracts them
# once the period ages out — so this table stays small and is a serving
# cache, not a usage archive.
#
# Read-only from the Rails side.
class UsageRealtimeProjection < ApplicationRecord
  belongs_to :organization
  belongs_to :subscription
  belongs_to :charge

  scope :covering, ->(time) { where("period_charges_from <= ? AND period_charges_to >= ?", time, time) }

  def readonly?
    true
  end
end

# == Schema Information
#
# Table name: usage_realtime_projections
# Database name: primary
#
#  aggregation_type    :string           not null
#  code                :string           not null
#  events_count        :bigint           default(0), not null
#  grouped_by          :string           default("{}"), not null, primary key
#  last_event_at       :datetime
#  last_ingested_at    :datetime
#  period_charges_from :datetime         not null
#  period_charges_to   :datetime         not null
#  units               :decimal(, )      default(0.0), not null
#  billing_period_id   :uuid             not null, primary key
#  charge_filter_id    :string           default(""), not null, primary key
#  charge_id           :uuid             not null, primary key
#  organization_id     :uuid             not null
#  plan_id             :uuid
#  subscription_id     :uuid             not null, primary key
#
# Indexes
#
#  idx_usage_realtime_projections_on_org_and_subscription  (organization_id,subscription_id)
#
