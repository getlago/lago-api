# frozen_string_literal: true

module Wallets
  class ExpireService < BaseService
    Result = BaseResult[:wallet]

    def initialize(wallet:)
      @wallet = wallet

      super
    end

    def call
      if wallet.active? && wallet.invoice_usage_on_expiration?
        subscriptions.find_each { |subscription| invoice_usage(subscription) }
      end

      # Applying the wallet credits updates its row, which bumps lock_version.
      Wallets::TerminateService.call!(wallet: wallet.reload)

      result.wallet = wallet
      result
    end

    private

    attr_reader :wallet

    def subscriptions
      wallet.customer.subscriptions.active.joins(:plan).where(plans: {amount_currency: wallet.currency})
    end

    def invoice_usage(subscription)
      invoice_result = Invoices::ProgressiveBilling::WalletTerminationService.call(wallet:, subscription:)

      # An idempotency error means a previous run already invoiced this subscription for this wallet.
      if invoice_result.failure? && !invoice_result.error.is_a?(Idempotency::IdempotencyError)
        invoice_result.raise_if_error!
      end
    end
  end
end
