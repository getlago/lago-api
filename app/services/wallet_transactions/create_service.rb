# frozen_string_literal: true

module WalletTransactions
  class CreateService < BaseService
    def create(**args)
      return result unless valid?(**args)

      if args[:paid_credits]
        handle_paid_credits(
          wallet: result.current_wallet,
          paid_credits: args[:paid_credits],
        )
      end

      if args[:granted_credits]
        handle_granted_credits(
          wallet: result.current_wallet,
          granted_credits: args[:granted_credits],
        )
      end
    end

    private

    def handle_paid_credits(wallet:, paid_credits:)
      # TODO
    end

    def handle_granted_credits(wallet:, granted_credits:)
      granted_credits_amount = BigDecimal(granted_credits)

      return if granted_credits_amount.zero?

      ActiveRecord::Base.transaction do
        WalletTransaction.create!(
          wallet: wallet,
          transaction_type: :inbound,
          amount: wallet.rate_amount * granted_credits_amount,
          credit_amount: granted_credits_amount,
          status: :settled,
          settled_at: Time.current,
        )

        Wallets::Balance::IncreaseService.new(wallet: wallet, credits_amount: granted_credits_amount).call
      end
    end

    def valid?(**args)
      WalletTransactions::ValidateService.new(result, **args).valid?
    end
  end
end
