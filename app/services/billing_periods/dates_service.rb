# frozen_string_literal: true

module BillingPeriods

  class DatesService < BaseService
    Result = BaseResult[:period_from, :period_to, :next_billing_at]

    def initialize()
      super
    end

    def call
      result
    end

    private
  end
end
