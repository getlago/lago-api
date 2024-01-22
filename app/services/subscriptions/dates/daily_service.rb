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
        return billing_date if plan.pay_in_advance? || terminated_pay_in_arrear?

        date
      end

      def compute_to_date(from_date = compute_from_date)
        from_date
      end

      def compute_charges_from_date
        # NOTE: when subscription is terminated, we must bill on the current day
        return billing_date if terminated?
        return compute_from_date if plan.pay_in_arrear?

        base_date
      end

      def compute_charges_to_date
        compute_charges_from_date
      end

      def compute_next_end_of_period
        billing_date.end_of_day
      end

      def compute_previous_beginning_of_period(date)
        # NOTE: Watchout for this - https://github.com/Pressingly/lagu-api/issues/24
        # date.beginning_of_day
        date
      end

      def compute_duration(*)
        DAY_DURATION
      end

      alias compute_charges_duration compute_duration
    end
  end
end
