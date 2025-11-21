# frozen_string_literal: true

module Invoices
  class IssuingDateService
    def initialize(customer:, recurring: false)
      @customer = customer
      @recurring = recurring
    end

    def grace_period_adjustment
      return grace_period unless recurring

      send("#{anchor}_#{adjustment}")
    end

    private

    attr_reader :customer, :recurring

    def current_period_end_keep_anchor
      -1
    end

    def current_period_end_align_with_finalization_date
      grace_period
    end

    def next_period_start_keep_anchor
      0
    end

    def next_period_start_align_with_finalization_date
      grace_period
    end

    def grace_period
      customer.applicable_invoice_grace_period
    end

    def anchor
      customer.applicable_subscription_invoice_issuing_date_anchor
    end

    def adjustment
      customer.applicable_subscription_invoice_issuing_date_adjustment
    end
  end
end
