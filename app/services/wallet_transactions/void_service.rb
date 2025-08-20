# frozen_string_literal: true

module WalletTransactions
  class VoidService < BaseService
    def initialize(wallet:, wallet_credit:, from_source: :manual, metadata: {}, credit_note_id: nil, priority: 50)
      @wallet = wallet
      @wallet_credit = wallet_credit
      @from_source = from_source
      @metadata = metadata
      @credit_note_id = credit_note_id
      @priority = priority

      super
    end

    def call
      return result if wallet_credit.credit_amount.zero?

      ActiveRecord::Base.transaction do
        wallet_transaction = CreateService.call!(
          wallet:,
          wallet_credit:,
          transaction_type: :outbound,
          status: :settled,
          settled_at: Time.current,
          source: from_source,
          transaction_status: :voided,
          metadata:,
          credit_note_id:,
          priority:
        ).wallet_transaction
        Wallets::Balance::DecreaseService.new(wallet:, wallet_transaction:).call
        result.wallet_transaction = wallet_transaction
      end

      result
    end

    private

    attr_reader :wallet, :wallet_credit, :from_source, :metadata, :credit_note_id, :priority
  end
end
