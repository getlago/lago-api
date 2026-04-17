# frozen_string_literal: true

class SubscriptionRateSchedule < ApplicationRecord
  include PaperTrailTraceable

  belongs_to :organization
  belongs_to :subscription
  belongs_to :product_item, -> { with_discarded }
  belongs_to :rate_schedule, -> { with_discarded }

  has_many :cycles, class_name: "SubscriptionRateScheduleCycle", dependent: :destroy

  STATUSES = {pending: "pending", active: "active", terminated: "terminated"}.freeze

  enum :status, STATUSES, validate: true

  validates :intervals_billed, numericality: {greater_than_or_equal_to: 0}

  def create_billing_cycle!
    if rate_schedule.pay_in_advance?
      from = next_billing_date
      to = advance_date(next_billing_date)
    else
      to = next_billing_date
      from = retreat_date(next_billing_date)
    end

    cycles.create!(
      organization:,
      cycle_index: intervals_billed,
      from_datetime: from,
      to_datetime: to
    )
  end

  def advance_billing!
    update!(
      intervals_billed: intervals_billed + 1,
      next_billing_date: advance_date(next_billing_date)
    )
  end

  private

  def advance_date(from)
    rs = rate_schedule
    offset = rs.billing_interval_count

    case rs.billing_interval_unit
    when "day" then from + offset.days
    when "week" then from + offset.weeks
    when "month" then from + offset.months
    when "year" then from + offset.years
    end
  end

  def retreat_date(from)
    rs = rate_schedule
    offset = rs.billing_interval_count

    case rs.billing_interval_unit
    when "day" then from - offset.days
    when "week" then from - offset.weeks
    when "month" then from - offset.months
    when "year" then from - offset.years
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
#  index_subscription_rate_schedules_on_organization_id   (organization_id)
#  index_subscription_rate_schedules_on_product_item_id   (product_item_id)
#  index_subscription_rate_schedules_on_rate_schedule_id  (rate_schedule_id)
#  index_subscription_rate_schedules_on_subscription_id   (subscription_id)
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (product_item_id => product_items.id)
#  fk_rails_...  (rate_schedule_id => rate_schedules.id)
#  fk_rails_...  (subscription_id => subscriptions.id)
#
