# frozen_string_literal: true

module WalletTransactions
  module Payments
    class GeneratePaymentUrlService < BaseService
      include Customers::PaymentProviderFinder

      def initialize(wallet_transaction:)
        @wallet_transaction = wallet_transaction
        super
      end

      def call
        puts @wallet_transaction
      end
    end
  end
end
