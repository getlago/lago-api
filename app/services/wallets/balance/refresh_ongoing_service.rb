# frozen_string_literal: true

module Wallets
  module Balance
    class RefreshOngoingService < BaseService
      def initialize(wallet:)
        @wallet = wallet
        super
      end

      def call
        total_amount = customer.active_subscriptions.sum do |subscription|
          ::Invoices::CustomerUsageService.call(
            nil, # current_user
            customer_id: customer.external_id,
            subscription_id: subscription.external_id,
            organization_id: customer.organization_id,
          ).invoice.total_amount
        end
        credits_amount = total_amount.to_f.fdiv(wallet.rate_amount)
        Wallets::Balance::DecreaseOngoingService.call(wallet:, credits_amount:).raise_if_error!

        result.wallet = wallet
        result
      end

      private

      attr_reader :wallet

      delegate :customer, to: :wallet
    end
  end
end
