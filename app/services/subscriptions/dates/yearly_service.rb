# frozen_string_literal: true

module Subscriptions
  module Dates
    class YearlyService < Subscriptions::DatesService
      private

      def compute_base_date
        billing_date - 1.year
      end

      def monthly_service
        @monthly_service ||= Subscriptions::Dates::MonthlyService.new(subscription, billing_date)
      end

      def compute_from_date
        if terminated_pay_in_arrear?
          return subscription.anniversary? ? previous_anniversary_day(billing_date) : billing_date.beginning_of_year
        end

        subscription.anniversary? ? previous_anniversary_day(base_date) : base_date.beginning_of_year
      end

      def compute_to_date
        return from_date.end_of_year if subscription.calendar? || subscription_date.yday == 1

        year = from_date.year + 1
        month = from_date.month
        day = subscription_date.day - 1

        build_date(year, month, day)
      end

      def compute_charges_from_date
        return from_date unless plan.bill_charges_monthly

        monthly_service.compute_from_date(billing_date - 1.month)
      end

      def compute_next_end_of_period(date)
        return date.end_of_year if calendar?

        year = date.year
        month = subscription_date.month
        day = subscription_date.day

        # NOTE: we need the last day of the period, and not the first of the next one
        result_date = build_date(year, month, day) - 1.day
        return result_date if result_date >= date

        build_date(year + 1, month, day) - 1.day
      end

      def previous_anniversary_day(date)
        year = date.month < subscription_date.month ? date.year - 1 : date.year
        month = subscription_date.month
        day = subscription_date.day

        build_date(year, month, day)
      end
    end
  end
end
