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

  def update_next_billing_date!
    return if started_at.nil?

    new_intervals_billed = intervals_billed + 1
    billing_start = started_at.to_date
    count = new_intervals_billed * rate_schedule.billing_interval_count

    next_date = case rate_schedule.billing_interval_unit
    when "day"
      billing_start + count.days
    when "week"
      billing_start + count.weeks
    when "month"
      billing_start + count.months
    when "year"
      billing_start + count.years
    end

    update!(intervals_billed: new_intervals_billed, next_billing_date: next_date)
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
