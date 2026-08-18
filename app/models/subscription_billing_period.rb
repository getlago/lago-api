# frozen_string_literal: true

# Charge-period boundaries for a subscription: the period covering now, plus the next one.
#
# Maintained by the services that move a subscription's billing dates, so the row is committed with
# the change itself, and reconciled on rollover by Clock::RefreshSubscriptionBillingPeriodsJob.
#
# Lets a consumer key usage by billing period without recomputing the boundaries, which stay owned
# by Subscriptions::DatesService. Derived data: hard-deleted, never soft-deleted.
#
# period_from/period_to hold the CHARGES boundaries, not the subscription-fee ones. The two differ
# when a yearly or semiannual plan bills its charges monthly.
class SubscriptionBillingPeriod < ApplicationRecord
  SCOPE_TYPES = %w[Subscription].freeze

  # How far back the rollover sweep looks for periods that have just ended. Has to cover a clock
  # outage: a rollover that falls out of the window is only materialized at the following one.
  ROLLOVER_LOOKBACK = 1.day

  belongs_to :organization
  belongs_to :subscription
  belongs_to :customer

  validates :scope_type, presence: true, inclusion: {in: SCOPE_TYPES}
  validates :period_from, :period_to, presence: true
  validate :period_to_after_period_from

  scope :covering, ->(time) { where(period_from: ..time, period_to: time..) }
  scope :expired, ->(time = Time.current) { where(period_to: ..time) }

  # Periods that ended within `lookback` of `time` and whose scope has no period starting after
  # `time`: the rollover has not been materialized yet.
  #
  # Both halves matter. Closed periods are kept, so `expired` alone matches every period a
  # subscription ever had and a sweep driven by it would re-enqueue the whole history on every
  # tick, forever. And without the successor check the same subscription would come back on every
  # tick until the window slid past it, rather than dropping out as soon as it has been rolled.
  scope :awaiting_rollover, ->(time = Time.current, lookback: ROLLOVER_LOOKBACK) {
    successor = unscoped
      .select(1)
      .from("subscription_billing_periods later")
      .where("later.scope_id = subscription_billing_periods.scope_id")
      .where("later.period_from > ?", time)

    where(period_to: (time - lookback)..time).where.not(successor.arel.exists)
  }

  private

  def period_to_after_period_from
    return if period_from.nil? || period_to.nil?
    return if period_to > period_from

    errors.add(:period_to, :must_be_after_period_from)
  end
end

# == Schema Information
#
# Table name: subscription_billing_periods
# Database name: primary
#
#  id              :uuid             not null, primary key
#  period_from     :datetime         not null
#  period_to       :datetime         not null
#  scope_type      :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  customer_id     :uuid             not null
#  organization_id :uuid             not null
#  scope_id        :uuid             not null
#  subscription_id :uuid             not null
#
# Indexes
#
#  index_subscription_billing_periods_on_customer_id               (customer_id)
#  index_subscription_billing_periods_on_organization_id           (organization_id)
#  index_subscription_billing_periods_on_period_to                 (period_to)
#  index_subscription_billing_periods_on_scope_id_and_period_from  (scope_id,period_from) UNIQUE
#  index_subscription_billing_periods_on_subscription_id           (subscription_id)
#  subscription_billing_periods_no_overlapping_periods             (scope_id, tsrange(period_from, period_to, '[]'::text)) USING gist
#
# Foreign Keys
#
#  fk_rails_...  (customer_id => customers.id)
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (subscription_id => subscriptions.id)
#
