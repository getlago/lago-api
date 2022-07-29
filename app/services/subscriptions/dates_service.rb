# frozen_string_literal: true

module Subscriptions
  class DatesService < BaseService
    def initialize(subscription, timestamp)
      @subscription = subscription

      # NOTE: timestamp is the billing day
      #       It should be the end of the billing period + 1 day
      #       When subscription is terminated, it is the termination day
      @timestamp = timestamp

      super(nil)
    end

    def previous_period_from_date
      from_date = case plan.interval.to_sym
                  when :weekly
                    weekly_from_date
                  when :monthly
                    monthly_from_date
                  when :yearly
                    yearly_from_date
                  else
                    raise NotImplementedError
      end

      # NOTE: On first billing period, subscription might start after the computed start of period
      #       ei: if we bill on beginning of period, and user registered on the 15th, the invoice should
      #       start on the 15th (subscription date) and not on the 1st
      from_date = subscription.started_at.to_date if from_date < subscription.started_at

      from_date
    end

    def terminated_pay_in_arrear?
      # NOTE: In case of termination or upgrade when we are terminating old plan (paying in arrear),
      #       we should take to the beginning of the billing period
      subscription.terminated? && plan.pay_in_arrear? && !subscription.downgraded?
    end

    def previous_period_to_date

    end

    def previous_period_charges_from_date

    end

    private

    attr_accessor :subscription, :timestamp

    delegate :plan, :subscription_date, to: :subscription

    def billing_date
      # NOTE: issue with termination on start date
      @billing_date ||= Time.zone.at(timestamp).to_date - 1.day
    end

    def weekly_from_date
      if terminated_pay_in_arrear?
        return subscription.anniversary? ? previous_weekly_anniversary_day : billing_date.beginning_of_week
      end

      subscription.anniversary? ? billing_date - 1.week : billing_date.beginning_of_week
    end

    def monthly_from_date
      if terminated_pay_in_arrear?
        return subscription.anniversary? ? previous_monthly_anniversary_day : billing_date.beginning_of_month
      end

      subscription.anniversary? ? billing_date - 1.month : billing_date.beginning_of_month
    end

    def yearly_from_date
      if terminated_pay_in_arrear?
        return subscription.anniversary? ? previous_yearly_anniversary_day : billing_date.beginning_of_year
      end

      subscription.anniversary? ? billing_date - 1.year : billing_date.beginning_of_year
    end

    def previous_weekly_anniversary_day
      days_before = (billing_date.wday + subscription_date.wday) % 7 + 1
      billing_date - days_before
    end

    def previous_monthly_anniversary_day
      year = nil
      month = nil
      day = subscription_date.day

      if billing_date.day <= subscription_date.day
        year = billing_date.month == 1 ? billing_date.year - 1 : billing_date.year
        month = billing_date.month == 1 ? 12 : billing_date.month - 1
      else
        year = billing_date.year
        month = billing_date.month
      end

      # NOTE: Handle leap years and anniversary day > 28
      day_count_in_month = Time.days_in_month(month, year)
      day = day_count_in_month if day_count_in_month < day

      Date.new(year, month, day)
    end

    def previous_yearly_anniversary_day
      year = billing_date.month < subscription_date.month ? billing_date.year - 1 : billing_date.year
      month = subscription_date.month
      day = subscription_date.day

      # NOTE: Handle leap years
      day_count_in_month = Time.days_in_month(month, year)
      day = day_count_in_month if day_count_in_month < day

      Date.new(year, month, day)
    end
  end
end
