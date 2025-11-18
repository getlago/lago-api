# frozen_string_literal: true

module Invoices
  class IssuingDateService < BaseService
    attr_reader :customer, :recurring

    def initialize(customer:, recurring: false)
      @customer = customer
      @recurring = recurring
      super
    end

    def base_date(timestamp)
      date = if recurring && current_period_end?
        timestamp - 1.day
      else
        timestamp
      end

      date.in_time_zone(customer.applicable_timezone).to_date
    end

    def grace_period
      period = customer.applicable_invoice_grace_period

      return period unless recurring
      return 0 if keep_anchor?

      current_period_end? ? period + 1 : period
    end

    def grace_period_diff(old_grace_period)
      diff = customer.applicable_invoice_grace_period - old_grace_period

      return diff unless recurring
      return 0 if keep_anchor?

      diff
    end

    private

    def current_period_end?
      customer.applicable_subscription_invoice_issuing_date_anchor == "current_period_end"
    end

    def keep_anchor?
      customer.applicable_subscription_invoice_issuing_date_adjustment == "keep_anchor"
    end
  end
end
