# frozen_string_literal: true

module WalletTransactions
  module Payments
    class GeneratePaymentUrlService < BaseService
      include Customers::PaymentProviderFinder

      def initialize(wallet_transaction:)
        @wallet_transaction = wallet_transaction
        @provider = wallet_transaction.wallet.customer.payment_provider
        super
      end

      def call
        return result.not_found_failure!(resource: "wallet_transaction") if wallet_transaction.blank?
        return result.single_validation_failure!(error_code: "no_linked_payment_provider") unless provider

      end

      private

      attr_reader :wallet_transaction, :provider
    end
  end
end
