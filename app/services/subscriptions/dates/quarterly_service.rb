# frozen_string_literal: true

module Subscriptions
  module Dates
    class QuarterlyService < Subscriptions::DatesService
      private

      def compute_from_date(date = base_date)
        if plan.pay_in_advance? || terminated_pay_in_arrears?
          return subscription.anniversary? ? previous_anniversary_day(billing_date) : billing_date.beginning_of_quarter
        end

        subscription.anniversary? ? previous_anniversary_day(date) : date.beginning_of_quarter
      end

      def compute_charges_from_date
        if terminated?
          return subscription.anniversary? ? previous_anniversary_day(billing_date) : billing_date.beginning_of_quarter
        end

        return compute_from_date if plan.pay_in_arrears?
        return base_date.beginning_of_quarter if calendar?

        previous_anniversary_day(base_date)
      end

      def compute_charges_to_date
        return compute_charges_from_date.end_of_quarter if calendar?

        compute_to_date(compute_charges_from_date)
      end

      # NOTE: `from_date` is not necessarily the beginning of the period: on a subscription resulting
      #       from an upgrade, it is clamped to `started_at` while the anniversary is inherited from the
      #       previous subscription. The duration is the one of the whole period, so it is measured from
      #       the beginning of the period holding `from_date`.
      def compute_duration(from_date:)
        period_start = compute_previous_beginning_of_period(from_date.to_date)

        (compute_to_date(period_start).to_date + 1.day - period_start).to_i
      end

      alias_method :compute_charges_duration, :compute_duration
      alias_method :compute_fixed_charges_duration, :compute_charges_duration
      alias_method :compute_fixed_charges_from_date, :compute_charges_from_date
      alias_method :compute_fixed_charges_to_date, :compute_charges_to_date

      def compute_base_date
        # NOTE: if subscription anniversary is on last day of month and current month days count
        #       is less than month anniversary day count, we need to use the last day of the previous month
        if subscription.anniversary? && last_day_of_month?(billing_date) && (billing_date.day < subscription_at.day)
          if (billing_date - 3.months).end_of_month.day >= subscription_at.day
            return (billing_date - 3.months).end_of_month.change(day: subscription_at.day)
          end

          return (billing_date - 3.months).end_of_month
        end

        billing_date - 3.months
      end

      def compute_to_date(from_date = compute_from_date)
        if subscription.calendar? || (subscription_at.day == 1 && [1, 4, 7, 10].include?(subscription_at.month))
          return from_date.end_of_quarter
        end

        next_anniversary(from_date) - 1.day
      end

      # `compute_to_date` is the day before this, so an anniversary always opens a period and never
      # also closes the previous one.
      def next_anniversary(from_date)
        next_period_month = from_date.to_date >> 3

        build_date(
          next_period_month.year,
          next_period_month.month,
          anniversary_day_in(next_period_month.year, next_period_month.month)
        )
      end

      # NOTE: the period is resolved from its own anniversary, not from `billing_date.month`, which is
      #       not necessarily a billing month and would advance the period one month at a time.
      def compute_next_end_of_period
        return billing_date.end_of_quarter if calendar?

        compute_to_date(previous_anniversary_day(billing_date))
      end

      def compute_previous_beginning_of_period(date)
        return date.beginning_of_quarter if calendar?

        previous_anniversary_day(date)
      end

      def previous_anniversary_day(date)
        year = nil
        month = nil

        billing_months = [
          (subscription_at.month % 12).zero? ? 12 : (subscription_at.month % 12),
          ((subscription_at.month + 3) % 12).zero? ? 12 : ((subscription_at.month + 3) % 12),
          ((subscription_at.month + 6) % 12).zero? ? 12 : ((subscription_at.month + 6) % 12),
          ((subscription_at.month + 9) % 12).zero? ? 12 : ((subscription_at.month + 9) % 12)
        ].sort

        # This is the case when we terminate subscription on On February 10 but anniversary date is on
        # 5 of March. In that case we need to fetch billing period in previous year
        if should_find_billing_date_in_previous_year?(date, billing_months)
          year = date.year - 1
          month = billing_months[3]
        # In case of termination that is in the middle of the year, previous period anniversary date has to be returned
        elsif should_find_previous_billing_date?(date, billing_months)
          year = date.year
          month = billing_months.rfind { |m| m < date.month }
        else
          year = date.year
          month = date.month
        end

        build_date(year, month, anniversary_day_in(year, month))
      end

      def should_find_billing_date_in_previous_year?(date, billing_months)
        return true if date.month < billing_months[0]

        (date.month == billing_months[0]) && should_find_previous_billing_date?(date, billing_months)
      end

      def should_find_previous_billing_date?(date, billing_months)
        # NOTE: checked first. A non-billing month always resolves to an earlier billing month, and
        #       falling through to the same-month branch below would instead walk the period forward
        #       one month at a time.
        return true if billing_months.exclude?(date.month)

        anniversary_day = anniversary_day_in(date.year, date.month)

        date.day < anniversary_day
      end
    end
  end
end
