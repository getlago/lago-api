# frozen_string_literal: true

module WalletTransactions
  module Create
    class FromCreditAmountService < BaseService
      Result = BaseResult[:wallet_transaction]

      def initialize(credit_amount:, **args)
        super(**args)
        @credit_amount = credit_amount
      end

      def call
        currency = wallet.currency_for_balance
        result.wallet_transaction = wallet.wallet_transactions.create!(
          amount: (wallet.rate_amount * credit_amount).round(currency.exponent),
          credit_amount:,
          status:,
          transaction_type:,
          source: from_source,
          transaction_status:,
          invoice_requires_successful_payment:,
          metadata:,
          settled_at:,
          credit_note_id:,
          invoice_id:
        )
        result
      end

      private
    end
  end
end
