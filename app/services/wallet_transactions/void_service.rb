# frozen_string_literal: true

module WalletTransactions
  class VoidService < BaseService
    def initialize(wallet:, wallet_credit:, **transaction_params)
      @wallet = wallet
      @wallet_credit = wallet_credit
      @transaction_params = transaction_params.slice(
        :source,
        :metadata,
        :priority,
        :credit_note_id,
        :name
      )

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
          transaction_status: :voided,
          **transaction_params
        ).wallet_transaction

        Wallets::Balance::DecreaseService.new(wallet:, wallet_transaction:).call
        result.wallet_transaction = wallet_transaction
      end

      after_commit do
        if wallet_transaction.should_sync_wallet_transaction?
          Integrations::Aggregator::WalletTransactions::CreateJob.perform_later(wallet_transaction:)
        end
      end

      result
    end

    private

    attr_reader :wallet, :wallet_credit, :transaction_params
  end
end
