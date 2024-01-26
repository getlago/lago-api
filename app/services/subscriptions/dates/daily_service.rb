# frozen_string_literal: true

module Subscriptions
  module Dates
    class DailyService < Subscriptions::DatesService
      DAY_DURATION = 1

      private

      def compute_base_date
        billing_date - 1.day
      end

      def compute_from_date(date = base_date)
        if plan.pay_in_advance? || terminated_pay_in_arrear?
          return subscription.anniversary? ? previous_anniversary_day(billing_date) : billing_date
        end

        subscription.anniversary? ? previous_anniversary_day(date) : date
      end

      def compute_to_date(from_date = compute_from_date)
        from_date
      end

      def compute_charges_from_date
        # NOTE: when subscription is terminated, we must bill on the current day
        if terminated?
          return subscription.anniversary? ? previous_anniversary_day(billing_date) : billing_date
        end

        return compute_from_date if plan.pay_in_arrear?
        return base_date if calendar?

        previous_anniversary_day(base_date)
      end

      def compute_charges_to_date
        compute_charges_from_date
      end

      def compute_next_end_of_period
        return billing_date.end_of_day if calendar?

        billing_date + 24.hours
      end

      def compute_previous_beginning_of_period(date)
        # NOTE: Watchout for this - https://github.com/Pressingly/lagu-api/issues/24
        # date.beginning_of_day
        return date if calendar?

        previous_anniversary_day(date)
      end

      def previous_anniversary_day(date)
        return date if date >= subscription_at

        date - 24.hours
      end

      def compute_duration(*)
        DAY_DURATION
      end

      alias compute_charges_duration compute_duration
    end
  end
end
