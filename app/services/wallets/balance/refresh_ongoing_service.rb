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
            customer: customer,
            subscription: subscription
          ).invoice.total_amount
        end
        usage_credits_amount = total_amount.to_f.fdiv(wallet.rate_amount)
        Wallets::Balance::UpdateOngoingService.call(wallet:, usage_credits_amount:).raise_if_error!

        result.wallet = wallet
        result
      end

      private

      attr_reader :wallet

      delegate :customer, to: :wallet
    end
  end
end
