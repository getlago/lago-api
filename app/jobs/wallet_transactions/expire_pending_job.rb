# frozen_string_literal: true

module WalletTransactions
  class ExpirePendingJob < ApplicationJob
    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_PAYMENTS"])
        :payments
      else
        :providers
      end
    end

    unique :until_executed, on_conflict: :log

    retry_on ::Stripe::RateLimitError, wait: :polynomially_longer, attempts: 6
    retry_on ::Stripe::APIConnectionError, wait: :polynomially_longer, attempts: 6

    def perform(wallet_transaction)
      WalletTransactions::ExpirePendingService.call!(wallet_transaction:)
    end
  end
end
