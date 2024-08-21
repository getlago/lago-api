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
        lifetime_usage.recalculate_current_usage = false
        lifetime_usage.current_usage_amount_refreshed_at = Time.current
      end
      if lifetime_usage.recalculate_invoiced_usage
        lifetime_usage.invoiced_usage_amount_cents = calculate_invoiced_usage_amount_cents
        lifetime_usage.recalculate_invoiced_usage = false
        lifetime_usage.invoiced_usage_amount_refreshed_at = Time.current
      end
      lifetime_usage.save!

      result.lifetime_usage = lifetime_usage
      result
    end

    private

    delegate :subscription, to: :lifetime_usage

    def calculate_invoiced_usage_amount_cents
      invoices = subscription.invoices.finalized
      invoices.sum { |invoice| invoice.fees.charge.sum(:amount_cents) }
    end

    def calculate_current_usage_amount_cents
      result = Invoices::CustomerUsageService.call(
        nil, # current_user
        customer: subscription.customer,
        subscription: subscription
      )
      result.usage.amount_cents
    end

    attr_accessor :lifetime_usage
  end
end
