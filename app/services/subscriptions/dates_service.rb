# frozen_string_literal: true

module Subscriptions
  class DatesService
    def self.new_instance(subscription, billing_date)
      klass = case subscription.plan.interval&.to_sym
              when :weekly
                Subscriptions::Dates::WeeklyService
              when :monthly
                Subscriptions::Dates::MonthlyService
              when :yearly
                Subscriptions::Dates::YearlyService
              else
                raise NotImplementedError
      end

      klass.new(subscription, billing_date)
    end

    def initialize(subscription, billing_date)
      @subscription = subscription

      # NOTE: Billing date should usually be the end of the billing period + 1 day
      #       When subscription is terminated, it is the termination day
      @billing_date = billing_date.to_date
    end

    def from_date
      return @from_date if @from_date

      @from_date = compute_from_date

      # NOTE: On first billing period, subscription might start after the computed start of period
      #       ie: if we bill on beginning of period, and user registered on the 15th, the invoice should
      #       start on the 15th (subscription date) and not on the 1st
      @from_date = subscription.started_at.to_date if @from_date < subscription.started_at

      @from_date
    end

    def to_date
      return @to_date if @to_date

      @to_date = compute_to_date

      @to_date = subscription.terminated_at.to_date if subscription.terminated? && @to_date > subscription.terminated_at

      # NOTE: When price plan is configured as `pay_in_advance`, subscription creation will be
      #       billed immediatly. An invoice must be generated for it with only the subscription fee.
      #       The invoicing period will be only one day: the subscription day
      @to_date = subscription.started_at.to_date if plan.pay_in_advance? && subscription.fees.subscription_kind.none?

      @to_date
    end

    def charges_from_date
      date = compute_charges_from_date
      date = subscription.started_at.to_date if date < subscription.started_at

      date
    end

    def next_end_of_period(date)
      compute_next_end_of_period(date)
    end

    private

    attr_accessor :subscription, :billing_date

    delegate :plan, :subscription_date, :calendar?, to: :subscription

    def base_date
      @base_date ||= compute_base_date
    end

    def terminated_pay_in_arrear?
      # NOTE: In case of termination or upgrade when we are terminating old plan (paying in arrear),
      #       we should take to the beginning of the billing period
      subscription.terminated? && plan.pay_in_arrear? && !subscription.downgraded?
    end

    # NOTE: Handle leap years and anniversary date > 28
    def build_date(year, month, day)
      days_count_in_month = Time.days_in_month(month, year)
      day = days_count_in_month if days_count_in_month < day

      Date.new(year, month, day)
    end

    def compute_from_date
      raise NotImplementedError
    end

    def compute_to_date
      raise NotImplementedError
    end

    def compute_charges_from_date
      raise NotImplementedError
    end

    def compute_next_end_of_period(date)
      raise NotImplementedError
    end
  end
end
