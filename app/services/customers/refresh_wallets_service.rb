# frozen_string_literal: true

module Customers
  class RefreshWalletsService < BaseService
    Result = BaseResult[:usage_amount_cents, :wallets, :allocation_rules]

    def initialize(customer:, include_generating_invoices: false)
      @customer = customer
      @include_generating_invoices = include_generating_invoices

      super
    end

    def call
      usage_amount_cents = customer.active_subscriptions.map do |subscription|
        invoice = ::Invoices::CustomerUsageService.call!(customer:, subscription:).invoice

        billed_progressive_invoice_subscriptions = ::Subscriptions::ProgressiveBilledAmount
          .call(subscription:, include_generating_invoices:)
          .invoice_subscriptions

        {
          billed_progressive_invoice_subscriptions:,
          invoice:,
          subscription:
        }
      end

      allocation_rules = Wallets::BuildAllocationRulesService.call!(customer:).allocation_rules

      customer.wallets.active.find_each do |wallet|
        Wallets::Balance::RefreshOngoingUsageService.call!(
          wallet:,
          usage_amount_cents:,
          allocation_rules:
        )
      end

      result.usage_amount_cents = usage_amount_cents
      result.allocation_rules = allocation_rules
      result.wallets = customer.wallets.active.reload
      result
    rescue BaseService::FailedResult => e
      e.result
    end

    private

    attr_reader :customer, :include_generating_invoices
  end
end
