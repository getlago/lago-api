# frozen_string_literal: true

class SubscriptionRateSchedule < ApplicationRecord
  include PaperTrailTraceable

  belongs_to :organization
  belongs_to :subscription
  belongs_to :product_item, -> { with_discarded }
  belongs_to :rate_schedule, -> { with_discarded }

  STATUSES = {pending: "pending", active: "active", terminated: "terminated"}.freeze

  enum :status, STATUSES, validate: true

  validates :intervals_billed, numericality: {greater_than_or_equal_to: 0}

  def exhausted?
    intervals_to_bill.present? && intervals_billed >= intervals_to_bill
  end

  # The date after which this rate schedule has no more cycles to bill.
  # Returns nil if there is no cycle limit (intervals_to_bill is nil).
  def end_date
    return nil if intervals_to_bill.nil? || started_at.nil?

    billing_date_for(intervals_to_bill)
  end

  # Returns the start date of the current billing period.
  def current_period_started_at
    billing_date_for(intervals_billed)
  end

  def update_next_billing_date!(billed: false)
    return if started_at.nil?

    self.intervals_billed += 1 if billed

    update!(intervals_billed:, next_billing_date: billing_date_for(intervals_billed + 1))
  end

  private

  # Returns the nth billing boundary date.
  #
  # Two billing modes determine when invoices are generated:
  #
  # Anniversary (billing_anchor_date nil, prorated: false, or daily interval):
  #   Billing dates are relative to the subscription's started_at.
  #   started_at is NOT a billing date, so the first billing is one full period later.
  #   Signup Mar 15, monthly → Apr 15, May 15, Jun 15 ...
  #
  # Calendar (billing_anchor_date present + prorated: true + non-daily interval):
  #   Billing dates align to the billing_anchor_date. The billing_anchor_date IS the first billing date (stub).
  #   Date arithmetic preserves the billing_anchor_date's relevant component:
  #     weekly  → same day of week as billing_anchor_date
  #     monthly → same day of month as billing_anchor_date
  #     yearly  → same month + day as billing_anchor_date
  #   Signup Mar 15, billing_anchor_date Mar 20, monthly → Mar 20 (stub), Apr 20, May 20 ...
  def billing_date_for(n)
    if calendar_mode?
      return started_at.to_date if n.zero?

      add_interval(subscription.billing_anchor_date, (n - 1) * rate_schedule.billing_interval_count)
    else
      add_interval(started_at.to_date, n * rate_schedule.billing_interval_count)
    end
  end

  def calendar_mode?
    subscription&.billing_anchor_date.present? &&
      rate_schedule.prorated &&
      rate_schedule.billing_interval_unit != "day"
  end

  def add_interval(date, count)
    case rate_schedule.billing_interval_unit
    when "day" then date + count.days
    when "week" then date + count.weeks
    when "month" then date + count.months
    when "year" then date + count.years
    end
  end
end

# == Schema Information
#
# Table name: subscription_rate_schedules
# Database name: primary
#
#  id                :uuid             not null, primary key
#  ended_at          :datetime
#  intervals_billed  :integer          default(0), not null
#  intervals_to_bill :integer
#  next_billing_date :date
#  started_at        :datetime
#  status            :enum             not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  organization_id   :uuid             not null
#  product_item_id   :uuid             not null
#  rate_schedule_id  :uuid             not null
#  subscription_id   :uuid             not null
#
# Indexes
#
#  index_subscription_rate_schedules_on_next_billing_date  (next_billing_date)
#  index_subscription_rate_schedules_on_organization_id    (organization_id)
#  index_subscription_rate_schedules_on_product_item_id    (product_item_id)
#  index_subscription_rate_schedules_on_rate_schedule_id   (rate_schedule_id)
#  index_subscription_rate_schedules_on_subscription_id    (subscription_id)
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (product_item_id => product_items.id)
#  fk_rails_...  (rate_schedule_id => rate_schedules.id)
#  fk_rails_...  (subscription_id => subscriptions.id)
#
