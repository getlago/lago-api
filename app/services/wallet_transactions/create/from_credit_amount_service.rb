# frozen_string_literal: true

module WalletTransactions
  module Create
    class FromCreditAmountService < BaseService
      Result = BaseResult[:wallet_transaction]

      def initialize(credit_amount:, **args)
        super(**args)
        @credit_amount = credit_amount
        currency = wallet.currency_for_balance
        @amount = (wallet.rate_amount * credit_amount).round(currency.exponent)
      end
    end
  end
end
