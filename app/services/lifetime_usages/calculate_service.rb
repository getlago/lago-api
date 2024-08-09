# frozen_string_literal: true

module LifetimeUsages
  class CalculateService < BaseService
    def initialize(lifetime_usage:)
      @lifetime_usage = lifetime_usage
      super
    end

    def call
      if lifetime_usage.recalculate_current_usage
        lifetime_usage.current_usage_amount_cents = calculate_current_usage_amount_cents
      end
      if lifetime_usage.recalculate_invoiced_usage
        lifetime_usage.invoiced_usage_amount_cents = calculate_invoiced_usage_amount_cents
      end

      result.lifetime_usage = lifetime_usage
      result
    end

    private

    def calculate_invoiced_usage_amount_cents
      invoices = subscription.invoices.finalized
      invoices.sum { |invoice| invoice.fees.charge.sum(:amount_cents) }
    end

    def calculate_current_usage_amount_cents
      result = Invoices::CustomerUsageService.call(
        nil,
        customer_id: lifetime_usage.subscription.customer_id,
        subscription_id: lifetime_usage.subscription_id
      )
      result.usage.amount_cents
    end

    attr_accessor :lifetime_usage
  end
end
