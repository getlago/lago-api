# frozen_string_literal: true

module Subscriptions
  module Dates
    class YearlyService < Subscriptions::DatesService
      def first_month_in_yearly_period?
        return billing_date.month == 1 if calendar?

        monthly_service.compute_from_date(billing_date).month == subscription_date.month
      end

      private

      def compute_base_date
        billing_date - 1.year
      end

      def monthly_service
        @monthly_service ||= Subscriptions::Dates::MonthlyService.new(subscription, billing_date, current_usage)
      end

      def compute_from_date
        if plan.pay_in_advance? || terminated_pay_in_arrear?
          return subscription.anniversary? ? previous_anniversary_day(billing_date) : billing_date.beginning_of_year
        end

        subscription.anniversary? ? previous_anniversary_day(base_date) : base_date.beginning_of_year
      end

      def compute_to_date(from_date = compute_from_date)
        return from_date.end_of_year if subscription.calendar? || subscription_date.yday == 1

        year = from_date.year + 1
        month = from_date.month
        day = subscription_date.day - 1

        build_date(year, month, day)
      end

      def compute_charges_from_date
        return monthly_service.compute_charges_from_date if plan.bill_charges_monthly

        if terminated?
          return subscription.anniversary? ? previous_anniversary_day(billing_date) : billing_date.beginning_of_year
        end

        return from_date if plan.pay_in_arrear?
        return base_date.beginning_of_year if calendar?

        previous_anniversary_day(base_date)
      end

      def compute_charges_to_date
        return monthly_service.compute_charges_to_date if plan.bill_charges_monthly
        return compute_charges_from_date.end_of_year if calendar?

        compute_to_date(compute_charges_from_date)
      end

      def compute_next_end_of_period
        return billing_date.end_of_year if calendar?

        year = billing_date.year
        month = subscription_date.month
        day = subscription_date.day

        # NOTE: we need the last day of the period, and not the first of the next one
        result_date = build_date(year, month, day) - 1.day
        return result_date if result_date >= billing_date

        build_date(year + 1, month, day) - 1.day
      end

      def compute_previous_beginning_of_period(date)
        return date.beginning_of_year if calendar?

        previous_anniversary_day(date)
      end

      def previous_anniversary_day(date)
        year = date.month < subscription_date.month ? date.year - 1 : date.year
        month = subscription_date.month
        day = subscription_date.day

        build_date(year, month, day)
      end

      def compute_duration(from_date:)
        return Time.days_in_year(from_date.year) if calendar?

        year = from_date.year
        # NOTE: if after February we must check if next year is a leap year
        year += 1 if from_date.month > 2

        Time.days_in_year(year)
      end

      def compute_charges_duration(from_date:)
        return monthly_service.compute_charges_duration(from_date: from_date) if plan.bill_charges_monthly

        compute_duration(from_date: from_date)
      end
    end
  end
end
