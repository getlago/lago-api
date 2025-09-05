# frozen_string_literal: true

module WalletTransactions
  class CreateService < BaseService
    Result = BaseResult[:wallet_transaction]

    def initialize(wallet:, wallet_credit:, **transaction_params)
      @wallet = wallet
      @wallet_credit = wallet_credit
      @transaction_params = transaction_params

      super
    end

    def call
      result.wallet_transaction = wallet.wallet_transactions.create!(
        **transaction_params.slice(
          :credit_note_id,
          :invoice_id,
          :invoice_requires_successful_payment,
          :name,
          :priority,
          :settled_at,
          :source,
          :status,
          :transaction_type,
          :transaction_status
        ),
        organization_id: wallet.organization_id,
        amount:,
        credit_amount:,
        metadata: transaction_params[:metadata] || []
      )

      result
    end

    private

    attr_reader :wallet, :wallet_credit, :transaction_params

    delegate :credit_amount, :amount, to: :wallet_credit
  end
end
