# frozen_string_literal: true

# Persisted charge-period boundaries per subscription, maintained ahead of
# time (current + next period) by Clock::RefreshSubscriptionBillingPeriodsJob.
#
# Consumed via CDC by the realtime usage pipeline (extra/risingwave) so that
# event-driven aggregation can be keyed by billing period while the date
# logic stays in Ruby (Subscriptions::DatesService).
#
# `customer_id` is denormalized from the subscription so period rows can be
# read without a second lookup. `scope_type` / `scope_id` reserve room for
# scope-specific period grids (charge- or plan-level); they are not written
# yet — subscription-level rows carry NULLs.
class SubscriptionBillingPeriod < ApplicationRecord
  belongs_to :organization
  belongs_to :subscription
  belongs_to :customer

  validates :period_from, :period_to, presence: true

  scope :covering, ->(time) { where("period_from <= ? AND period_to >= ?", time, time) }
end

# == Schema Information
#
# Table name: subscription_billing_periods
# Database name: primary
#
#  id              :uuid             not null, primary key
#  period_from     :datetime         not null
#  period_to       :datetime         not null
#  scope_type      :string
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  customer_id     :uuid             not null
#  organization_id :uuid             not null
#  scope_id        :uuid
#  subscription_id :uuid             not null
#
# Indexes
#
#  idx_on_subscription_id_period_from_63bcfaba9e          (subscription_id,period_from) UNIQUE
#  index_subscription_billing_periods_on_customer_id      (customer_id)
#  index_subscription_billing_periods_on_organization_id  (organization_id)
#
# Foreign Keys
#
#  fk_rails_...  (customer_id => customers.id)
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (subscription_id => subscriptions.id)
#
