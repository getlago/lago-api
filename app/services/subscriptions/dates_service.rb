# frozen_string_literal: true

module Subscriptions
  class DatesService
    def initialize(subscription, billing_date)
      @subscription = subscription

      # NOTE: Billing date should usually be the end of the billing period + 1 day
      #       When subscription is terminated, it is the termination day
      @billing_date = billing_date.to_date
    end

    def from_date
      return @from_date if @from_date

      @from_date = case plan.interval.to_sym
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
      #       ie: if we bill on beginning of period, and user registered on the 15th, the invoice should
      #       start on the 15th (subscription date) and not on the 1st
      @from_date = subscription.started_at.to_date if @from_date < subscription.started_at

      @from_date
    end

    def to_date
      return @to_date if @to_date

      @to_date = case plan.interval.to_sym
                 when :weekly
                   weekly_to_date
                 when :monthly
                   monthly_to_date
                 when :yearly
                   yearly_to_date
                 else
                   raise NotImplementedError
      end

      if subscription.terminated? && @to_date > subscription.terminated_at
        # NOTE: When subscription is terminated, we cannot generate an invoice for a period after the termination
        @to_date = if %i[pending active].include?(subscription.next_subscription&.status&.to_sym)
          subscription.terminated_at.to_date - 1.day # TODO: check with multiple plan, and upgrade
        else
          subscription.terminated_at.to_date
        end

        # TODO: from_date / to_date of invoices should be timestamps so that to_date = subscription.terminated_at
      end

      # NOTE: When price plan is configured as `pay_in_advance`, subscription creation will be
      #       billed immediatly. An invoice must be generated for it with only the subscription fee.
      #       The invoicing period will be only one day: the subscription day
      @to_date = subscription.started_at.to_date if plan.pay_in_advance? && subscription.fees.subscription_kind.none?

      @to_date
    end

    def charges_from_date
      charges_from_date = if plan.yearly? && plan.bill_charges_monthly
        monthly_from_date(billing_date - 1.month)
      else
        from_date
      end

      charges_from_date = subscription.started_at.to_date if charges_from_date < subscription.started_at

      # NOTE: when upgrading, we bill the fees from the start of the complete period (from previous plan)
      #       and not only from the start of the current subscription
      # TODO: This should be chalenged
      return upgraded_charges_from_date(charges_from_date) if first_period_after_upgrade?

      charges_from_date
    end

    def next_end_of_period(date, plan)
      case plan.interval.to_sym
      when :weekly
        next_end_of_weekly_period(date)
      when :monthly
        next_end_of_monthly_period(date)
      when :yearly
        next_end_of_yearly_period(date)
      else
        raise NotImplementedError
      end
    end

    private

    attr_accessor :subscription, :billing_date

    delegate :plan, :subscription_date, :calendar?, to: :subscription

    def base_date
      @base_date ||= case plan.interval.to_sym
                     when :weekly
                       billing_date - 1.week
                     when :monthly
                       billing_date - 1.month
                     when :yearly
                       billing_date - 1.year
                     else
                       raise NotImplementedError
      end
    end

    def subscription_day_name
      @subscription_day_name ||= subscription_date.strftime('%A').downcase.to_sym
    end

    def terminated_pay_in_arrear?
      # NOTE: In case of termination or upgrade when we are terminating old plan (paying in arrear),
      #       we should take to the beginning of the billing period
      subscription.terminated? && plan.pay_in_arrear? && !subscription.downgraded?
    end

    def weekly_from_date
      if terminated_pay_in_arrear?
        return subscription.anniversary? ? billing_date.prev_occurring(subscription_day_name) : billing_date.beginning_of_week
      end

      subscription.anniversary? ? base_date.prev_occurring(subscription_day_name) : base_date.beginning_of_week
    end

    def weekly_to_date
      from_date + 6.days
    end

    def monthly_from_date(date = base_date)
      if terminated_pay_in_arrear?
        return subscription.anniversary? ? previous_monthly_anniversary_day(billing_date) : billing_date.beginning_of_month
      end

      subscription.anniversary? ? previous_monthly_anniversary_day(date) : date.beginning_of_month
    end

    def monthly_to_date
      return from_date.end_of_month if subscription.calendar? || subscription_date.day == 1

      year = from_date.year
      month = from_date.month + 1
      day = subscription_date.day - 1

      if month > 12
        month = 1
        year += 1
      end

      build_date(year, month, day)
    end

    def yearly_from_date
      if terminated_pay_in_arrear?
        return subscription.anniversary? ? previous_yearly_anniversary_day(billing_date) : billing_date.beginning_of_year
      end

      subscription.anniversary? ? previous_yearly_anniversary_day(base_date) : base_date.beginning_of_year
    end

    def yearly_to_date
      return from_date.end_of_year if subscription.calendar? || subscription_date.yday == 1

      year = from_date.year + 1
      month = from_date.month
      day = subscription_date.day - 1

      build_date(year, month, day)
    end

    def previous_monthly_anniversary_day(date)
      year = nil
      month = nil
      day = subscription_date.day

      if date.day <= day
        year = date.month == 1 ? date.year - 1 : date.year
        month = date.month == 1 ? 12 : date.month - 1
      else
        year = date.year
        month = date.month
      end

      build_date(year, month, day)
    end

    def previous_yearly_anniversary_day(date)
      year = date.month < subscription_date.month ? date.year - 1 : date.year
      month = subscription_date.month
      day = subscription_date.day

      build_date(year, month, day)
    end

    # NOTE: Handle leap years and anniversary date > 28
    def build_date(year, month, day)
      days_count_in_month = Time.days_in_month(month, year)
      day = days_count_in_month if days_count_in_month < day

      Date.new(year, month, day)
    end

    def first_period_after_upgrade?
      return false unless subscription.previous_subscription
      return false unless subscription.previous_subscription.upgraded?

      subscription.fees.charge_kind.none?
    end

    def upgraded_charges_from_date(from_date)
      # TODO: check with previous plan interval, we might have a rabit hole in here...
      case plan.interval.to_sym
      when :weekly
        weekly_upgraded_charges_from_date(from_date)
      when :monthly
        monthly_upgraded_charges_from_date(from_date)
      when :yearly
        if subscription.previous_subscription.plan.bill_charges_monthly?
          monthly_upgraded_charges_from_date(from_date)
        else
          yearly_upgraded_charges_from_date(from_date)
        end
      else
        raise NotImplementedError
      end
    end

    def weekly_upgraded_charges_from_date(from_date)
      return from_date.beginning_of_week if subscription.calendar?

      from_date.prev_occurring(subscription_day_name)
    end

    def monthly_upgraded_charges_from_date(from_date)
      return from_date.beginning_of_month if subscription.calendar?

      previous_monthly_anniversary_day(from_date)
    end

    def yearly_upgraded_charges_from_date(from_date)
      return from_date.beginning_of_year if subscription.calendar?

      previous_yearly_anniversary_day(from_date)
    end

    def next_end_of_weekly_period(date)
      return date.end_of_week if calendar?
      return date if date.wday == (subscription_date - 1.day).wday

      # NOTE: we need the last day of the period, and not the first of the next one
      date.next_occurring(subscription_day_name) - 1.day
    end

    def next_end_of_monthly_period(date)
      return date.end_of_month if calendar?

      year = date.year
      month = date.month
      day = subscription_date.day

      # NOTE: we need the last day of the period, and not the first of the next one
      result_date = build_date(year, month, day) - 1.day
      return result_date if result_date >= date

      month += 1
      if month > 12
        month = 1
        year += 1
      end

      build_date(year, month, day) - 1.day
    end

    def next_end_of_yearly_period(date)
      return date.end_of_year if calendar?

      year = date.year
      month = subscription_date.month
      day = subscription_date.day

      # NOTE: we need the last day of the period, and not the first of the next one
      result_date = build_date(year, month, day) - 1.day
      return result_date if result_date >= date

      build_date(year + 1, month, day) - 1.day
    end
  end
end
