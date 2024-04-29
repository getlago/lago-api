# frozen_string_literal: true

module WalletTransactions
  class CreateService < BaseService
    def initialize(organization:, params:)
      @organization = organization
      @params = params

      super
    end

    def call
      return result unless valid?

      wallet_transactions = []
      @source = params[:source] || :manual

      if params[:paid_credits]
        transaction = handle_paid_credits(wallet: result.current_wallet, paid_credits: params[:paid_credits])
        wallet_transactions << transaction
      end

      if params[:granted_credits]
        transaction = handle_granted_credits(
          wallet: result.current_wallet,
          granted_credits: params[:granted_credits],
          reset_consumed_credits: ActiveModel::Type::Boolean.new.cast(params[:reset_consumed_credits]),
        )
        wallet_transactions << transaction
      end

      if params[:voided_credits]
        void_result = WalletTransactions::VoidService.call(
          wallet: result.current_wallet,
          credits: params[:voided_credits],
          from_source: source,
        )
        wallet_transactions << void_result.wallet_transaction
      end

      transactions = wallet_transactions.compact
      if organization.webhook_endpoints.any?
        transactions.each { |wt| SendWebhookJob.perform_later('wallet_transaction.created', wt.reload) }
      end

      result.wallet_transactions = transactions
      result
    end

    private

    attr_reader :organization, :params, :source

    def handle_paid_credits(wallet:, paid_credits:)
      paid_credits_amount = BigDecimal(paid_credits)

      return if paid_credits_amount.zero?

      wallet_transaction = WalletTransaction.create!(
        wallet:,
        transaction_type: :inbound,
        amount: wallet.rate_amount * paid_credits_amount,
        credit_amount: paid_credits_amount,
        status: :pending,
        source:,
        transaction_status: :purchased,
      )

      BillPaidCreditJob.perform_later(wallet_transaction, Time.current.to_i)

      wallet_transaction
    end

    def handle_granted_credits(wallet:, granted_credits:, reset_consumed_credits: false)
      granted_credits_amount = BigDecimal(granted_credits)

      return if granted_credits_amount.zero?

      ActiveRecord::Base.transaction do
        wallet_transaction = WalletTransaction.create!(
          wallet:,
          transaction_type: :inbound,
          amount: wallet.rate_amount * granted_credits_amount,
          credit_amount: granted_credits_amount,
          status: :settled,
          settled_at: Time.current,
          source:,
          transaction_status: :granted,
        )

        Wallets::Balance::IncreaseService.new(
          wallet:,
          credits_amount: granted_credits_amount,
          reset_consumed_credits:,
        ).call

        wallet_transaction
      end
    end

    def valid?
      WalletTransactions::ValidateService.new(result, **params.merge(organization_id: organization.id)).valid?
    end
  end
end
