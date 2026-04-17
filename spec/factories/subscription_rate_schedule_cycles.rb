# frozen_string_literal: true

FactoryBot.define do
  factory :subscription_rate_schedule_cycle do
    organization
    subscription_rate_schedule { association(:subscription_rate_schedule, organization:) }
    cycle_index { 0 }
    from_datetime { Time.current.beginning_of_month }

    to_datetime do
      rs = subscription_rate_schedule.rate_schedule
      interval = rs.billing_interval_count

      case rs.billing_interval_unit
      when "day" then from_datetime + interval.days
      when "week" then from_datetime + interval.weeks
      when "month" then from_datetime + interval.months
      when "year" then from_datetime + interval.years
      else from_datetime + 1.month
      end
    end
  end
end
