# frozen_string_literal: true

module WalletTransactions
  class VoidService < BaseService
    def initialize(wallet:, credits_amount:, from_source: :manual, metadata: {}, credit_note_id: nil)
      @wallet = wallet
      @credits_amount = credits_amount
      @from_source = from_source
      @metadata = metadata
      @credit_note_id = credit_note_id

      super
    end

    def call
      return result if credits_amount.zero?

      ActiveRecord::Base.transaction do
        wallet_transaction = Create::FromCreditAmountService.call!(
          wallet:,
          transaction_type: :outbound,
          credit_amount: credits_amount,
          status: :settled,
          settled_at: Time.current,
          from_source:,
          transaction_status: :voided,
          metadata:,
          credit_note_id:
        ).wallet_transaction
        Wallets::Balance::DecreaseService.new(wallet:, wallet_transaction:).call
        result.wallet_transaction = wallet_transaction
      end

      result
    end

    private

    attr_reader :wallet, :credits_amount, :from_source, :metadata, :credit_note_id
  end
end
