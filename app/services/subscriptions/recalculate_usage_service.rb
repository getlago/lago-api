# frozen_string_literal: true

module Subscriptions
  class RecalculateUsageService < BaseService
    def initialize(subscription:)
      @subscription = subscription
      super
    end

    def call
      # NOTE: Force usage calculation to refresh cache
      calculate_current_usage

      # TODO(alerts): Implement the logic check alerts for the subscription

      lifetime_usage = LifetimeUsages::FlagRefreshFromSubscriptionService.call!(subscription:).lifetime_usage
      LifetimeUsages::RecalculateAndCheckJob.perform_later(lifetime_usage)

      result
    end

    private

    attr_reader :subscription

    delegate :customer, to: :subscription

    def calculate_current_usage
      Invoices::CustomerUsageService.call(customer:, subscription:, apply_taxes: false)
    end
  end
end
