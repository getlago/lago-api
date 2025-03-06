# frozen_string_literal: true

module WalletTransactions
  module Create
    class FromAmountService < BaseService
      Result = BaseResult[:wallet_transaction]

      def initialize(amount_cents:, **args)
        super(**args)
        currency = wallet.currency_for_balance
        @amount = amount_cents.round.fdiv(currency.subunit_to_unit)
        @credit_amount = amount.fdiv(wallet.rate_amount)
      end
    end
  end
end
