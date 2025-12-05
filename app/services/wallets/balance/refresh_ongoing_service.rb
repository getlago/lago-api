# frozen_string_literal: true

module Wallets
  module Balance
    class RefreshOngoingService < BaseService
      def initialize(wallet:, include_generating_invoices: false)
        @wallet = wallet
        @include_generating_invoices = include_generating_invoices
        super
      end

      def call
        usage_result = Customers::SubscriptionsUsageService.call(customer:, include_generating_invoices:)
        return usage_result if usage_result.failure?

        RefreshOngoingUsageService.call!(
          wallet:,
          fees: usage_result.fees,
          billed_usage_amount_cents: usage_result.billed_usage_amount_cents
        )

        result.wallet = wallet.reload
        result
      end

      private

      attr_reader :wallet, :include_generating_invoices

      delegate :customer, to: :wallet
    end
  end
end
