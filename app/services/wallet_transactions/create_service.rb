# frozen_string_literal: true

module WalletTransactions
  class CreateService < BaseService
    def create(**args)
      return result unless valid?(**args)

      wallet_transactions = []
      @source = args[:source] || :manual

      if args[:paid_credits]
        transaction = handle_paid_credits(wallet: result.current_wallet, paid_credits: args[:paid_credits])
        wallet_transactions << transaction
      end

      if args[:granted_credits]
        transaction = handle_granted_credits(
          wallet: result.current_wallet,
          granted_credits: args[:granted_credits],
          reset_consumed_credits: ActiveModel::Type::Boolean.new.cast(args[:reset_consumed_credits]),
        )
        wallet_transactions << transaction
      end

      result.wallet_transactions = wallet_transactions.compact
      result
    end

    private

    attr_reader :source

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
      )

      BillPaidCreditJob.perform_later(
        wallet_transaction,
        Time.current.to_i,
      )

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
        )

        Wallets::Balance::IncreaseService.new(
          wallet:,
          credits_amount: granted_credits_amount,
          reset_consumed_credits:,
        ).call

        wallet_transaction
      end
    end

    def valid?(**args)
      WalletTransactions::ValidateService.new(result, **args).valid?
    end
  end
end
