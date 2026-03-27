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

  # Computes and persists the next billing date for this rate schedule.
  #
  # Two billing modes determine when invoices are generated:
  #
  # Anniversary (anchor_date nil, prorated: false, or daily interval):
  #   Billing dates are relative to the subscription's started_at.
  #   started_at is NOT a billing date, so the first billing is one full period later.
  #   Signup Mar 15, monthly → Apr 15, May 15, Jun 15 ...
  #
  # Calendar (anchor_date present + prorated: true + non-daily interval):
  #   Billing dates align to the anchor. The anchor IS the first billing date (stub).
  #   Date arithmetic preserves the anchor's relevant component:
  #     weekly  → same day of week as anchor
  #     monthly → same day of month as anchor
  #     yearly  → same month + day as anchor
  #   Signup Mar 15, anchor Mar 20, monthly → Mar 20 (stub), Apr 20, May 20 ...
  #
  def update_next_billing_date!(billed: false)
    return if started_at.nil?

    self.intervals_billed += 1 if billed

    update!(intervals_billed:, next_billing_date: compute_next_billing_date)
  end

  private

  def compute_next_billing_date
    if calendar_mode?
      offset = intervals_billed * rate_schedule.billing_interval_count
      add_interval(subscription.anchor_date, offset)
    else
      offset = (intervals_billed + 1) * rate_schedule.billing_interval_count
      add_interval(started_at.to_date, offset)
    end
  end

  def calendar_mode?
    subscription&.anchor_date.present? &&
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
