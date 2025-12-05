# frozen_string_literal: true

module Customers
  class RefreshWalletsService < BaseService
    Result = BaseResult[:usage_amount_cents, :wallets]

    def initialize(customer:, include_generating_invoices: false)
      @customer = customer
      @include_generating_invoices = include_generating_invoices

      super
    end

    def call
      usage_amount_cents = customer.active_subscriptions.map do |subscription|
        invoice = ::Invoices::CustomerUsageService.call!(customer:, subscription:).invoice

        {
          total_usage_amount_cents: invoice.total_amount_cents,
          invoice:,
          subscription:
        }
      end

      customer.wallets.active.find_each do |wallet|
        Wallets::Balance::RefreshOngoingUsageService.call!(wallet:, usage_amount_cents:, include_generating_invoices:)
      end

      result.usage_amount_cents = usage_amount_cents
      result.wallets = customer.wallets.active.reload
      result
    rescue BaseService::FailedResult => e
      e.result
    end

    private

    attr_reader :customer, :include_generating_invoices
  end
end
