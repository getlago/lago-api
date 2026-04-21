# frozen_string_literal: true

module Subscriptions
  module RateSchedules
    class PlanOverrideService < BaseService
      def call
      end

      def update_customer_currency
        Customers::UpdateCurrencyService.call(
          customer:,
          currency: plan.amount_currency
        ).raise_if_error!
      end
    end
  end
end
