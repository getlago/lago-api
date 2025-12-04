# frozen_string_literal: true

module Customers
  class RefreshWalletsService < BaseService
    Result = BaseResult[:wallets]

    def initialize(customer:, include_generating_invoices: false)
      @customer = customer
      @include_generating_invoices = include_generating_invoices

      super
    end

    def call
      usage_result = SubscriptionsUsageService.call(customer:, include_generating_invoices:)
      return usage_result if usage_result.failure?

      customer.wallets.active.find_each do |wallet|
        Wallets::Balance::RefreshOngoingUsageService.call!(
          wallet:,
          fees: usage_result.fees,
          billed_usage_amount_cents: usage_result.billed_usage_amount_cents
        )
      end

      result.wallets = customer.wallets.active.reload
      result
    rescue BaseService::FailedResult => e
      e.result
    end

    private

    attr_reader :customer, :include_generating_invoices
  end
end
