# frozen_string_literal: true

module WalletTransactions
  class RecreditService < BaseService
    def initialize(wallet_transaction:)
      @wallet_transaction = wallet_transaction
      @wallet = wallet_transaction.wallet
      @customer = @wallet.customer
      @transaction_service = WalletTransactions::CreateService.new

      super
    end

    def call
      result.wallet_transaction = wallet_transaction

      return result.not_allowed_failure!(code: 'wallet_not_active') unless wallet.active?

      transaction_result = transaction_service.create(
        organization_id: customer.organization_id,
        wallet_id: wallet.id,
        granted_credits: wallet_transaction.credit_amount.to_s,
      )

      unless transaction_result.success?
        result.service_failure!(code: 'recredit_wallet_error', message: 'Failed to recredit the wallet')
      end

      result
    end

    private

    attr_reader :wallet_transaction, :wallet, :customer, :transaction_service
  end
end
