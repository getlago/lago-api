# frozen_string_literal: true

module Subscriptions
  module Dates
    class YearlyService < Subscriptions::DatesService
      def first_month_in_yearly_period?
        return billing_date.month == 1 if calendar?

        monthly_service.compute_from_date(billing_date).month == subscription_at.month
      end

      def first_month_in_first_yearly_period?
        return billing_date.month == 1 && billing_date.year == subscription_at.year if calendar?

        billing_from_date = monthly_service.compute_from_date(billing_date)
        billing_from_date.month == subscription_at.month && billing_from_date.year == subscription_at.year
      end

      private

      # When computing current usage (not billing), boundaries are always needed.
      # if bill_charges_monthly=true, charge boundaries should be filled
      # if bill_FIXED_charges_monthly=true, charge boundaries should be filled only for the first month of the period
      # For yearly plans with bill_charges_monthly=false, and bill_fixed_charges_monthly=false,
      # boundaries are always filled
      def should_fill_charges_boundaries?
        return true if current_usage
        return true if plan.bill_charges_monthly?

        return first_month_in_yearly_period? if plan.bill_fixed_charges_monthly?

        true
      end

      # if bill_fixed_charges_monthly=true, fixed charge boundaries should be filled
      # if bill_charges_monthly=true, fixed charge boundaries should be filled only for the first month of the period
      # For yearly plans with bill_charges_monthly=false, and bill_fixed_charges_monthly=false,
      # boundaries are always filled
      def should_fill_fixed_charges_boundaries?
        return true if plan.bill_fixed_charges_monthly?

        return first_month_in_yearly_period? if plan.bill_charges_monthly?

        true
      end

      def compute_base_date
        # NOTE: if subscription anniversary is on last day of month and current month days count
        #       is less than month anniversary day count, we need to use the last day of the previous month
        if subscription.anniversary? && last_day_of_month?(billing_date) && (billing_date.day < subscription_at.day)
          if (billing_date - 1.year).end_of_month.day >= subscription_at.day
            return (billing_date - 1.year).end_of_month.change(day: subscription_at.day)
          end

          return (billing_date - 1.year).end_of_month
        end

        billing_date - 1.year
      end

      def monthly_service
        @monthly_service ||= Subscriptions::Dates::MonthlyService.new(subscription, billing_date, current_usage)
      end

      def compute_from_date
        if plan.pay_in_advance? || terminated_pay_in_arrears?
          return subscription.anniversary? ? previous_anniversary_day(billing_date) : billing_date.beginning_of_year
        end

        subscription.anniversary? ? previous_anniversary_day(base_date) : base_date.beginning_of_year
      end

      def compute_to_date(from_date = compute_from_date)
        return from_date.end_of_year if subscription.calendar? || subscription_at.yday == 1

        year = from_date.year + 1
        month = from_date.month
        day = subscription_at.day - 1

        date = build_date(year, month, day)

        # NOTE: if subscription anniversary day is higher than the current last day of the month,
        #       subscription period, will end on the previous end of day
        return date - 1.day if last_day_of_month?(date) && subscription_at.day > date.day

        date
      end

      def compute_charges_from_date
        return monthly_service.compute_charges_from_date if plan.bill_charges_monthly

        if terminated?
          return subscription.anniversary? ? previous_anniversary_day(billing_date) : billing_date.beginning_of_year
        end

        return compute_from_date if plan.pay_in_arrears?
        return base_date.beginning_of_year if calendar?

        previous_anniversary_day(base_date)
      end

      def compute_charges_to_date
        return monthly_service.compute_charges_to_date if plan.bill_charges_monthly
        return compute_charges_from_date.end_of_year if calendar?

        compute_to_date(compute_charges_from_date)
      end

      def compute_fixed_charges_from_date
        return monthly_service.compute_fixed_charges_from_date if plan.bill_fixed_charges_monthly

        if terminated?
          return subscription.anniversary? ? previous_anniversary_day(billing_date) : billing_date.beginning_of_year
        end

        return compute_from_date if plan.pay_in_arrears?
        return base_date.beginning_of_year if calendar?

        previous_anniversary_day(base_date)
      end

      def compute_fixed_charges_to_date
        return monthly_service.compute_fixed_charges_to_date if plan.bill_fixed_charges_monthly
        return compute_fixed_charges_from_date.end_of_year if calendar?

        compute_to_date(compute_fixed_charges_from_date)
      end

      # NOTE: the period is resolved from its own anniversary rather than re-walked from the billing
      #       date, so there is a single derivation of the anniversary day.
      def compute_next_end_of_period
        return billing_date.end_of_year if calendar?

        compute_to_date(previous_anniversary_day(billing_date))
      end

      def compute_previous_beginning_of_period(date)
        return date.beginning_of_year if calendar?

        previous_anniversary_day(date)
      end

      def previous_anniversary_day(date)
        year = period_started_in_last_year?(date) ? (date.year - 1) : date.year
        month = subscription_at.month
        day = subscription_at.day

        build_date(year, month, day)
      end

      # NOTE: `from_date` is not necessarily the beginning of the period: on a subscription resulting
      #       from an upgrade, it is clamped to `started_at` while the anniversary is inherited from the
      #       previous subscription. The duration is the one of the whole period, so it is measured from
      #       the anniversary opening the period holding `from_date`.
      def compute_duration(from_date:)
        return Time.days_in_year(from_date.year) if calendar?

        period_start = previous_anniversary_day(from_date.to_date)

        (compute_to_date(period_start).to_date + 1.day - period_start).to_i
      end

      def compute_charges_duration(from_date:)
        return monthly_service.compute_charges_duration(from_date:) if plan.bill_charges_monthly

        compute_duration(from_date:)
      end

      def compute_fixed_charges_duration(from_date:)
        return monthly_service.compute_fixed_charges_duration(from_date:) if plan.bill_fixed_charges_monthly

        compute_duration(from_date:)
      end

      def period_started_in_last_year?(date)
        return true if date.month < subscription_at.month
        return false unless date.month == subscription_at.month

        # NOTE: a Feb 29 subscription has its anniversary on Feb 28 in a common year, so the raw
        #       subscription day would leave Feb 28 trailing the previous period.
        date.day < anniversary_day_in(date.year, subscription_at.month)
      end
    end
  end
end
